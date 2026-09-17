#!/usr/bin/env bash
#
# run_impl.sh — helper to build one implementation and benchmark specific scenario.
#
# Each scenario lives in its own folder under impls/ (impls/noloss/,
# impls/lossy/, impls/islands/), each folder should contain: an entry
# `node.c` (the file with run_node) plus any custom helper .c/.h files. # # This script installs the chosen folder's sources into mixnet/ (this 
# matches the 
# autograder behavior), rebuilds the `node` binary, and runs the matching 
# STP-convergence test-case
# in autotester mode.
#
# It prints the two lab metrics for every run -- total STP packets and
# inter-island STP packets (ignore for noloss / lossy). The autograder scores 
# the mean over 10 runs.
#
# Usage:
#     ./impls/run_impl.sh <scenario> [runs] [--impl PATH]
#
#   <scenario>   noloss | lossy | islands   (selects the topology / test-case)
#   [runs]       number of runs (default 1)
#   --impl PATH  build PATH instead of mixnet/ (a single .c file, built as
#                node.c, or a folder of sources) — e.g. an optimized per-scenario
#                solution such as impls/noloss/. mixnet/ is restored afterwards.
#
# By default (no --impl) it builds whatever is already in mixnet/ — i.e. your
# baseline solution — so the plain form gives the baseline numbers.
#
# Examples:
#     ./impls/run_impl.sh noloss                        # mixnet/ as-is (baseline), hybrid topology
#     ./impls/run_impl.sh lossy 10                      # mixnet/ as-is, 10 runs + stats
#     ./impls/run_impl.sh noloss --impl impls/noloss    # optimized impls/noloss/ folder
#     ./impls/run_impl.sh islands 10 --impl ../my_node.c        # arbitrary file
#     ./impls/run_impl.sh islands 10 --impl ../my_solution_dir  # arbitrary folder
#
# Env:
#     MIXNET_LOSS=25   ./impls/run_impl.sh lossy   # override the loss rate
#     MIXNET_STP_NORMALIZE=1 ./impls/run_impl.sh noloss  # tolerate a root
#                                                 # path-length offset (see handout)
#
set -euo pipefail

usage() { echo "usage: $0 <noloss|lossy|islands> [runs] [--impl PATH]" >&2; exit 1; }

NAME=""
RUNS=1
IMPL_OVERRIDE=""
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then NAME="$1"; shift; fi
while [ $# -gt 0 ]; do
    case "$1" in
        --impl|-i) IMPL_OVERRIDE="${2:-}"; shift 2 ;;
        --impl=*)  IMPL_OVERRIDE="${1#*=}"; shift ;;
        ''|*[!0-9]*) usage ;;              # not a number and not a known flag
        *) RUNS="$1"; shift ;;             # a bare integer => run count
    esac
done
[ -n "$NAME" ] || usage

case "$NAME" in
    noloss)  TESTCASE=testcase_stp_convergence_hybrid       ;;
    lossy)   TESTCASE=testcase_stp_convergence_hybrid_lossy ;;
    islands) TESTCASE=testcase_stp_convergence_islands      ;;
    *) usage ;;
esac

# Resolve repo layout relative to this script (works from any cwd).
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MIXNET="$ROOT/mixnet"
BIN="$ROOT/build/bin/lab/$TESTCASE"

IMMUTABLE="address.h config.h connection.h packet.h CMakeLists.txt"  # keep framework's
STATS=""

if [ -n "$IMPL_OVERRIDE" ]; then
    # Override: stage the given .c file / folder into mixnet/ (e.g. an optimized
    # per-scenario solution like impls/noloss/). mixnet/ is restored on exit.
    SRC="$IMPL_OVERRIDE"
    [ -e "$SRC" ] || { echo "error: implementation path not found: $SRC" >&2; exit 1; }

    # Stage the sources first, so nothing breaks if SRC lives inside mixnet/.
    STAGE="$(mktemp -d)"
    if [ -d "$SRC" ]; then cp -a "$SRC/." "$STAGE/"; else cp "$SRC" "$STAGE/node.c"; fi

    # Full backup of mixnet/, restored no matter how we exit.
    BK="$(mktemp -d)"
    cp -a "$MIXNET/." "$BK/"
    cleanup() { rm -rf "$MIXNET"; mv "$BK" "$MIXNET"; rm -rf "$STAGE"; [ -n "$STATS" ] && rm -f "$STATS"; return 0; }
    trap cleanup EXIT

    # Reset mixnet/ to just the immutable framework files, then install the
    # staged sources (skipping any immutable files the student may have included).
    find "$MIXNET" -maxdepth 1 -type f \
        ! -name address.h ! -name config.h ! -name connection.h \
        ! -name packet.h  ! -name CMakeLists.txt -delete
    for f in "$STAGE"/*; do
        b="$(basename "$f")"
        case " $IMMUTABLE " in *" $b "*) continue ;; esac
        cp "$f" "$MIXNET/"
    done
    [ -f "$MIXNET/node.c" ] || { echo "error: $SRC has no node.c (an entry file defining run_node is required)" >&2; exit 1; }
    [ -f "$MIXNET/node.h" ] || cp "$BK/node.h" "$MIXNET/"   # fall back to framework node.h
    echo ">> building '$NAME' from $(basename "$SRC") (staged into mixnet/) ..."
else
    # Default: build whatever is already in mixnet/ (your baseline lives here).
    # No staging, so mixnet/ is untouched and needs no backup/restore.
    [ -f "$MIXNET/node.c" ] || { echo "error: mixnet/ has no node.c" >&2; exit 1; }
    cleanup() { [ -n "$STATS" ] && rm -f "$STATS"; return 0; }
    trap cleanup EXIT
    echo ">> building '$NAME' from mixnet/ as-is (baseline) ..."
fi

mkdir -p "$ROOT/build"
( cd "$ROOT/build" && cmake .. >/dev/null && make node "$TESTCASE" >/dev/null )

echo ">> running $TESTCASE (${RUNS} run(s)) ..."

# Collect the two metrics for every run into a temp file: "converged total inter"
STATS="$(mktemp)"
for i in $(seq 1 "$RUNS"); do
    line="$("$BIN" -a 2>&1 | grep -E '^\[STP\]' | tail -1 || true)"
    if echo "$line" | grep -q 'converged=true'; then
        total="$(echo "$line" | grep -oE 'stp_packets_until_convergence=[0-9]+' | grep -oE '[0-9]+')"
        inter="$(echo "$line" | grep -oE 'inter_island_stp_packets=[0-9]+'      | grep -oE '[0-9]+')"
        printf 'run %2d: converged=true   total_stp=%-4s inter_island=%s\n' "$i" "$total" "$inter"
        echo "1 $total $inter" >> "$STATS"
    else
        printf 'run %2d: converged=false  (no score for this run)\n' "$i"
        echo "0 0 0" >> "$STATS"
    fi
done

# Summary: convergence count + min/mean/max of each metric over CONVERGED runs.
echo "------------------------------------------------------------"
awk -v runs="$RUNS" '
    { if ($1==1) { c++;
        ts+=$2; if (tmin==""||$2<tmin) tmin=$2; if ($2>tmax) tmax=$2;
        is+=$3; if (imin==""||$3<imin) imin=$3; if ($3>imax) imax=$3 } }
    END {
        printf "converged:            %d/%d\n", c, runs
        if (c>0) {
            printf "total STP packets     min=%d  mean=%.1f  max=%d\n", tmin, ts/c, tmax
            printf "inter-island STP      min=%d  mean=%.1f  max=%d\n", imin, is/c, imax
        }
        if (c<runs)
            printf "WARNING: only %d/%d runs converged -- the autograder needs 10/10 to score this scenario.\n", c, runs
    }' "$STATS"
