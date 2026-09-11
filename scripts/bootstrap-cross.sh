#!/bin/bash
# Reproducible clean bootstrap for the Mogrix IRIX cross environment.
#
# This works around the legacy setup-cross prerequisite cycle:
#   setup-cross historically required libsoft_float_stubs.a before it had
#   deployed irix-cc, while build-runtime-objects.sh needs irix-cc to create it.
#
# Current Mogrix links the real soft-float/compiler runtime from libgcc_s.so.1.
# The temporary empty archive below exists only to satisfy that old bootstrap
# check long enough for setup-cross to deploy the actual toolchain and runtimes.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${SGUG_STAGING:-/opt/sgug-staging/usr/sgug}"
CROSS="${IRIX_CROSS_BINDIR:-/opt/cross/bin}"
AR="${CROSS}/llvm-ar"

if [[ ! -x "$AR" ]]; then
    echo "ERROR: llvm-ar not found at $AR" >&2
    exit 1
fi

mkdir -p "$STAGING/lib32"

LEGACY_ARCHIVE="$STAGING/lib32/libsoft_float_stubs.a"
if [[ ! -f "$LEGACY_ARCHIVE" ]]; then
    echo "Seeding legacy bootstrap archive: $LEGACY_ARCHIVE"
    "$AR" rcs "$LEGACY_ARCHIVE"
fi

echo "Running mogrix setup-cross..."
(
    cd "$ROOT"
    uv run mogrix setup-cross
)

echo "Building/deploying runtime objects..."
"$ROOT/scripts/build-runtime-objects.sh"

echo

echo "Bootstrap complete."
echo "Next sanity check: compile and link a trivial C program with irix-cc."
