#!/usr/bin/env bash
#
# run_ec2.sh — run a mixnet convergence test-case across a cluster of servers
#              (e.g. 8 EC2 instances) over SSH, in the framework's manual mode.
#
# It starts the orchestrator on the first host in the hosts.txt file, launches one
# ./bin/node on EVERY host (pointed at the orchestrator's private IP), waits for
# the run to finish, and prints the orchestrator's output — which includes the
# "[STP] ... stp_packets_until_convergence=..." line you record for your plots.
#
# Prerequisites:
#   * SSH keypair set up in every host -- your EC2
#     keypair. 
#   * All hosts in one VPC/security group with TCP open among them (see README).
#
# Usage:
#   ./impls/run_ec2.sh <testcase> <hosts-file>
#
#   <testcase>     e.g. testcase_stp_convergence_line  (must be an 8-node test
#                  for an 8-host file; node count is fixed by the test-case)
#   <hosts-file>   one SSH target per line (user@host); blank lines and lines
#                  starting with '#' are ignored. One line per mixnet node.
#
# Env:
#   IMPL         OPTIONAL. Build a different implementation: a single .c file
#                (built as node.c) or a folder of sources. It's assembled into a
#                temp dir and shipped to each host's mixnet/ — the LOCAL mixnet/
#                is never modified. Unset (default) = ship mixnet/ as-is.
#   NODE_LOGS    OPTIONAL. If set (e.g. NODE_LOGS=1), always dump each host's node
#                stdout/stderr at the end — even on a converged run. Unset
#                (default) = dump the node logs only when the run did NOT converge.
#   REMOTE_DIR   path to the repo on each host        (default: cmu-mixnet-lab)
#   ORCH_IP      IP the nodes use to reach the orchestrator
#                (default: first host's private IP, via `hostname -I`)
#   SSH_KEY      path to your EC2 private key (.pem); wired in as `ssh -i`
#   SSH          ssh command                (default: ssh -o BatchMode=yes ...)
#   SYNC         rsync this tree to each host and (re-)configure + build first
#                (default: 1; set SYNC=0 to skip the ENTIRE toolchain+rsync+build
#                section once every host is already synced & built). SYNC=1 always
#                re-runs cmake so newly-added testcase*.cpp files (globbed at
#                configure time) get built; `make` is still incremental.
#
# Example:
#   SSH_KEY=<path to key> ./impls/run_ec2.sh testcase_stp_convergence_ring hosts.txt         # build mixnet/ as-is, sync+build+run
#   SSH_KEY=<path to key> IMPL=../student_impls/impl1.c ./impls/run_ec2.sh testcase_stp_convergence_line hosts.txt  # stage a different impl, then run
#   SSH_KEY=<path to key> SYNC=1 ./impls/run_ec2.sh testcase_stp_convergence_ring hosts.txt  # re-sync + re-configure (picks up new testcases) + incremental make
#   SSH_KEY=<path to key> SYNC=0 ./impls/run_ec2.sh testcase_stp_convergence_tree hosts.txt  # skip sync+build entirely, reuse the existing binaries
#   NODE_LOGS=1 IMPL=~/mixnet/node.c SSH_KEY=<path to key> ./impls/run_ec2.sh testcase_rtt_line hosts.txt  # ping/RTT: source node prints "RTT to 7: <ms> ms" (needs cp2 routing; see NODE_LOGS)
#
set -euo pipefail

TESTCASE="${1:-}"
HOSTS_FILE="${2:-}"
[ -n "$TESTCASE" ] && [ -n "$HOSTS_FILE" ] || {
    echo "usage: $0 <testcase> <hosts-file>" >&2; exit 1; }
[ -f "$HOSTS_FILE" ] || { echo "error: hosts file '$HOSTS_FILE' not found" >&2; exit 1; }
# Catch the common mistake of putting an env var (SYNC=0, IMPL=..., etc.) AFTER
# the command, where the shell treats it as an ignored positional arg. Env vars
# must precede the command: `SYNC=0 $0 <testcase> <hosts-file>`.
if [ "$#" -gt 2 ]; then
    shift 2
    echo "error: unexpected extra argument(s): $*" >&2
    echo "       env vars (SYNC=, IMPL=, SSH_KEY=, ...) must go BEFORE the command:" >&2
    echo "       SYNC=0 $0 $TESTCASE $HOSTS_FILE" >&2
    exit 1
fi

REMOTE_DIR="${REMOTE_DIR:-cmu-mixnet-lab}"
# If SSH_KEY is set, point ssh at that private key (and check it's usable).
SSH_KEY_OPT=""
if [ -n "${SSH_KEY:-}" ]; then
    [ -f "$SSH_KEY" ] || { echo "error: SSH_KEY '$SSH_KEY' not found" >&2; exit 1; }
    # SSH ignores keys with loose permissions; tighten if needed.
    [ "$(stat -f '%Lp' "$SSH_KEY" 2>/dev/null || stat -c '%a' "$SSH_KEY")" = "600" ] \
        || chmod 600 "$SSH_KEY"
    SSH_KEY_OPT="-i $SSH_KEY -o IdentitiesOnly=yes"
fi
SSH="${SSH:-ssh $SSH_KEY_OPT -o BatchMode=yes -o StrictHostKeyChecking=accept-new}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# Read non-empty, non-comment lines into HOSTS[]. The `|| [ -n "$line" ]` guard
# is essential: without it, a hosts file whose final line lacks a trailing
# newline silently drops that last host — which launches too few nodes and hangs
# the orchestrator waiting for a connection that never comes.
HOSTS=()
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"; line="$(echo "$line" | xargs || true)"
    [ -n "$line" ] && HOSTS+=("$line")
done < "$HOSTS_FILE"
[ "${#HOSTS[@]}" -gt 0 ] || { echo "error: no hosts in $HOSTS_FILE" >&2; exit 1; }

ORCH_HOST="${HOSTS[0]}"
echo ">> ${#HOSTS[@]} node host(s); orchestrator co-located on $ORCH_HOST"

# Which implementation to build on every host. By DEFAULT we ship whatever is
# already in mixnet/ (build it as-is). Set IMPL=/path/to/impl — a single .c file
# built as node.c, or a folder of sources — to build a different implementation.
# When IMPL is set we assemble it into a TEMP staging dir and rsync THAT onto each
# host's mixnet/; the LOCAL mixnet/ is never read-modified-writtend.
MIXNET="$ROOT/mixnet"
IMMUTABLE="address.h config.h connection.h packet.h CMakeLists.txt"  # keep framework's

# Kill remote processes on any exit (including Ctrl-C) and drop the temp stage.
# ssh has no PTY here, so killing the local client does NOT signal the remote
# proc; we must pkill explicitly. The orchestrator runs only on ORCH_HOST and
# must be killed too, or it keeps 9107 bound and the next run can't start. Guards
# let this run safely before ORCH_IP is resolved / nodes are launched.
cleanup() {
    [ -n "${STAGE:-}" ] && rm -rf "$STAGE"
    if [ -n "${ORCH_IP:-}" ]; then
        for h in "${HOSTS[@]}"; do
            # shellcheck disable=SC2086
            $SSH "$h" "pkill -f 'bin/node $ORCH_IP' >/dev/null 2>&1 || true" || true
        done
        # shellcheck disable=SC2086
        $SSH "$ORCH_HOST" "pkill -f 'bin/lab/$TESTCASE' >/dev/null 2>&1 || true" || true
    fi
    return 0
}
trap cleanup EXIT INT TERM

# If IMPL is set (and we're syncing), assemble the mixnet/ we want to ship into a
# temp dir STAGE = the framework's immutable headers taken from the real mixnet/,
# plus the impl's sources overlaid on top. The rsync loop ships STAGE to each
# host's mixnet/. The local mixnet/ is only ever READ here, never written.
STAGE=""
if [ "${SYNC:-1}" != "0" ]; then
    if [ -n "${IMPL:-}" ]; then
        [ -e "$IMPL" ] || { echo "error: IMPL not found: $IMPL" >&2; exit 1; }
        STAGE="$(mktemp -d)"
        # Framework files the build needs, copied from the (untouched) mixnet/.
        for f in $IMMUTABLE node.h; do
            [ -f "$MIXNET/$f" ] && cp "$MIXNET/$f" "$STAGE/"
        done
        # Overlay the impl: a single file becomes node.c; a folder's sources are
        # copied in (skipping any immutable files the impl may include).
        if [ -d "$IMPL" ]; then
            for f in "$IMPL"/*; do
                b="$(basename "$f")"
                case " $IMMUTABLE " in *" $b "*) continue ;; esac
                cp "$f" "$STAGE/"
            done
        else
            cp "$IMPL" "$STAGE/node.c"
        fi
        [ -f "$STAGE/node.c" ] || { echo "error: $IMPL has no node.c (an entry file defining run_node is required)" >&2; exit 1; }
        echo ">> building impl: $(basename "$IMPL")  (staged to a temp dir, shipped to each host's mixnet/; local mixnet/ untouched)"
    else
        echo ">> building mixnet/ as-is  (set IMPL=<file|dir> to build a different implementation)"
    fi
else
    echo ">> SYNC=0: reusing the EXISTING remote build; mixnet/ and any local edits are NOT deployed"
fi

# Sync + build the repo on every host (default on; SYNC=0 to skip). rsync
# provisions REMOTE_DIR from this local tree, so hosts need no repository access.
if [ "${SYNC:-1}" != "0" ]; then
    for h in "${HOSTS[@]}"; do
        # Only touch apt when cmake/g++ are missing; otherwise skip entirely
        # (no apt-get update) and say so, so a warm host isn't mistaken for a
        # reprovision.
        # shellcheck disable=SC2086
        $SSH "$h" "if command -v cmake >/dev/null && command -v g++ >/dev/null; then \
            echo '   toolchain present, skipping'; \
        else \
            echo '   installing toolchain (cmake + build-essential) ...'; \
            sudo apt-get update -qq && \
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential cmake && \
            echo '   toolchain ok'; \
        fi"
        echo ">> [$h] syncing + building ..."
        if [ -n "$STAGE" ]; then
            # Ship the whole tree EXCEPT mixnet/, then ship the assembled mixnet/
            # from the temp stage. The local mixnet/ is never sent or modified.
            rsync -az --delete \
                --exclude '.git' --exclude 'build' --exclude 'impls/submission.zip' \
                --exclude '/mixnet' \
                -e "$SSH" "$ROOT"/ "$h:$REMOTE_DIR"/
            rsync -az --delete -e "$SSH" "$STAGE"/ "$h:$REMOTE_DIR/mixnet"/
        else
            rsync -az --delete \
                --exclude '.git' --exclude 'build' --exclude 'impls/submission.zip' \
                -e "$SSH" "$ROOT"/ "$h:$REMOTE_DIR"/
        fi
        # Always (re-)configure with cmake, then build. Re-running cmake is cheap
        # for an unchanged tree, and it is REQUIRED to pick up newly-added source
        # files: testing/lab/CMakeLists.txt uses file(GLOB "testcase*.cpp"), which
        # is only evaluated at configure time — so a new RTT/convergence testcase
        # (e.g. testcase_rtt_tree.cpp) won't build (and run_ec2 can't find it)
        # unless cmake re-runs. `make` still does an incremental compile.
        # shellcheck disable=SC2086
        $SSH "$h" "cd '$REMOTE_DIR' && cmake -S . -B build >/dev/null && make -C build -j\$(nproc) >/dev/null && echo '   build ok'"
    done
fi

# Resolve the orchestrator IP the nodes will dial (its first private IP).
if [ -z "${ORCH_IP:-}" ]; then
    # shellcheck disable=SC2086
    ORCH_IP="$($SSH "$ORCH_HOST" "hostname -I | awk '{print \$1}'")"
fi
[ -n "$ORCH_IP" ] || { echo "error: could not determine ORCH_IP" >&2; exit 1; }
echo ">> orchestrator IP (as seen by nodes): $ORCH_IP"

# Start the orchestrator (no -a => manual mode). Tee its output so you see it
# live (tail -f style) AND keep a copy in $ORCH_LOG for the [STP] grep below.
# `stdbuf -oL -eL` line-buffers it so lines appear as they happen, not at exit.
ORCH_LOG="$(mktemp)"
echo ">> [$ORCH_HOST] starting orchestrator: $TESTCASE"
# shellcheck disable=SC2086
$SSH "$ORCH_HOST" "cd '$REMOTE_DIR/build' && stdbuf -oL -eL ./bin/lab/$TESTCASE" 2>&1 \
    | tee "$ORCH_LOG" &
ORCH_PID=$!

# Give the orchestrator a moment to bind 9107 before nodes dial in.
sleep 3

# Launch one node per host, all pointed at the orchestrator.
# Each node's stdout+stderr is captured to a per-host log so a node that fails
# to connect or dies on startup leaves a trace instead of vanishing silently.
NODE_LOG_DIR="$(mktemp -d)"
echo ">> node logs: $NODE_LOG_DIR"
NODE_PIDS=()
for h in "${HOSTS[@]}"; do
    echo ">> [$h] starting node -> $ORCH_IP:9107"
    safe="${h//[^A-Za-z0-9._-]/_}"
    # stdbuf -oL -eL line-buffers the node's output so each printed line is
    # flushed to the log immediately — otherwise the (block-buffered) output is
    # lost when the node is pkill'd at cleanup instead of exiting cleanly.
    # shellcheck disable=SC2086
    $SSH "$h" "cd '$REMOTE_DIR/build' && stdbuf -oL -eL ./bin/node $ORCH_IP 9107" \
        >"$NODE_LOG_DIR/$safe.log" 2>&1 &
    NODE_PIDS+=("$!")
done

# (cleanup + trap are installed near the top so the temp stage is removed and
#  remote processes are always reaped, even on an early failure or Ctrl-C.)

# Wait for the orchestrator run to complete, then show its result.
# (Output already streamed live above via tee; $ORCH_LOG is the captured copy.)
wait "$ORCH_PID" || true
echo "============================================================="
# Always surface the [STP] result line...
grep -E '^\[STP\]' "$ORCH_LOG" || echo "(no [STP] line — check the output above for errors)"
# ...and dump the per-host node logs when NODE_LOGS is set (inspect node output
# on ANY run, even a converged one), OR whenever the run did NOT converge (the
# default — includes converged=false, not just a total crash).
if [ -n "${NODE_LOGS:-}" ] || ! grep -q 'converged=true' "$ORCH_LOG"; then
    echo "---- per-host node logs ----"
    for f in "$NODE_LOG_DIR"/*.log; do
        echo "-------- ${f##*/} --------"
        cat "$f"
    done
fi
rm -f "$ORCH_LOG"
rm -rf "$NODE_LOG_DIR"
