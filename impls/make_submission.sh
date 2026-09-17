#!/usr/bin/env bash
#
#
# Each scenario is a self-contained folder holding a custom implementation
# of node.c and any helper .c/.h files:
#
#     impls/noloss/    Scenario 1  (hybrid, no loss)     -- REQUIRED
#     impls/lossy/     Scenario 2  (hybrid, lossy links) -- REQUIRED
#     impls/islands/   Scenario 3  (Hawaii islands)      -- OPTIONAL (extra credit)
#
# The autograder builds every .c in a scenario's folder together, so multi-file
# solutions work. The zip preserves the folder layout (noloss/node.c, ...).
#
# Usage:
#     ./impls/make_submission.sh                 # the impls/{noloss,lossy,islands}/ folders
#
# Produces submission.zip next to this script.
#
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
SRCROOT="${1:-$HERE}"
OUT="$HERE/submission.zip"
IMMUTABLE="address.h config.h connection.h packet.h CMakeLists.txt"  # never submit these

die()  { printf 'error: %s\n' "$1" >&2; exit 1; }
warn() { printf 'warning: %s\n'  "$1" >&2; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Stage one scenario into $STAGE/<name>/ from either a folder (impls/<name>/) or
# a legacy flat file (impls/<name>.c). Returns 0 if present, 1 if absent.
stage_scenario() {
    name="$1"
    dir="$SRCROOT/$name"
    if [ -d "$dir" ] && ls "$dir"/*.c >/dev/null 2>&1; then
        mkdir -p "$STAGE/$name"
        for f in "$dir"/*.c "$dir"/*.h; do
            [ -e "$f" ] || continue
            b="$(basename "$f")"
            case " $IMMUTABLE " in *" $b "*) continue ;; esac   # drop framework headers
            cp "$f" "$STAGE/$name/"
        done
    else
        return 1
    fi
    [ -f "$STAGE/$name/node.c" ] || die "$name/: no entry 'node.c' found (the file with run_node)"
    grep -q 'run_node' "$STAGE/$name/node.c" || \
        warn "$name/node.c has no run_node() — is this really your node implementation?"
    return 0
}

# --- Required scenarios ------------------------------------------------------
stage_scenario noloss || die "missing required scenario 'noloss' (expected an impls/noloss/ folder with node.c)"
stage_scenario lossy  || die "missing required scenario 'lossy' (expected an impls/lossy/ folder with node.c)"

# --- Optional scenario -------------------------------------------------------
have_islands=0
if stage_scenario islands; then have_islands=1; fi

# --- Build the zip (preserve the folder layout) ------------------------------
rm -f "$OUT"                                  # `zip` appends; start clean
( cd "$STAGE" && zip -r -q "$OUT" noloss lossy $( [ "$have_islands" = 1 ] && echo islands ) )

# --- Summary -----------------------------------------------------------------
echo "Created $OUT with:"
list_files() { ( cd "$STAGE/$1" && printf '    %s\n' *.c *.h 2>/dev/null | grep -v '\*' ); }
echo "  noloss/   (required)";  list_files noloss
echo "  lossy/    (required)";  list_files lossy
if [ "$have_islands" = 1 ]; then
    echo "  islands/  (extra credit)"; list_files islands
else
    echo "  islands/  — not included (optional extra credit; skipping)"
fi
echo "Upload submission.zip to Gradescope."
