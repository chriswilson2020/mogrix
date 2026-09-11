#!/bin/bash
# Reproducible clean bootstrap for the Mogrix IRIX cross environment.
#
# This works around two legacy setup-cross problems in current main:
#   1. setup-cross requires libsoft_float_stubs.a before it deploys irix-cc,
#      while the runtime builder needs irix-cc.
#   2. setup-cross does not deploy the tracked cross/bin/irix-cxx wrapper; it
#      creates irix-cxx by copying irix-cc, which cannot compile .cpp/.cc/.cxx.
#
# Current Mogrix links soft-float/compiler builtins from libgcc_s.so.1.  The
# seeded archive below exists only to get through the stale setup-cross check.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${SGUG_STAGING:-/opt/sgug-staging/usr/sgug}"
CROSS="${IRIX_CROSS_BINDIR:-/opt/cross/bin}"
AR="${CROSS}/llvm-ar"

if [[ ! -x "$AR" ]]; then
    echo "ERROR: llvm-ar not found at $AR" >&2
    exit 1
fi

mkdir -p "$STAGING/bin" "$STAGING/lib32"

# Predeploy the real C++ wrapper. setup-cross only synthesizes irix-cxx when the
# destination is missing, so this prevents it from replacing C++ support with a
# copy of the C-only wrapper.
install -m 0755 "$ROOT/cross/bin/irix-cxx" "$STAGING/bin/irix-cxx"

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
echo "C wrapper:   $STAGING/bin/irix-cc"
echo "C++ wrapper: $STAGING/bin/irix-cxx"
echo "Run scripts/test-cross-runtime.sh for compile/link smoke tests."
