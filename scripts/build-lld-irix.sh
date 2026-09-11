#!/bin/bash
# Build the fully patched LLVM 18 LLD required by Mogrix/IRIX.
#
# IMPORTANT: the canonical patch logic lives in lld-fixes/build-lld-irix.sh.
# The older implementation of this script only patched Writer.cpp and produced
# an LLD that did not understand the required `elf32btsmipn32_irix` emulation.
# Keep this entry point as the /opt/cross installer, but delegate the build to
# the complete patch set.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT/tmp/lld-irix-build"
SRC="$BUILD_ROOT/llvm-project-18.1.3.src"
DRIVER="$SRC/lld/ELF/Driver.cpp"
CANONICAL="$ROOT/lld-fixes/build-lld-irix.sh"
BUILT="$ROOT/tools/bin/ld.lld-irix-18"
DEST_DIR="/opt/cross/bin"

if [[ ! -f "$CANONICAL" ]]; then
    echo "ERROR: canonical LLD builder missing: $CANONICAL" >&2
    exit 1
fi

# A source tree touched by the historical partial builder contains the Writer
# patch but not the Driver.cpp `_irix` emulation support.  The canonical script
# used to treat the Writer marker as meaning *all* patches were present, so it
# would skip the missing Driver/SyntheticSections changes.  Re-extract from the
# cached tarball instead.  The ~LLVM source tarball itself is kept.
if [[ -d "$SRC" ]]; then
    if [[ ! -f "$DRIVER" ]] || ! grep -q 'ends_with("_irix")' "$DRIVER"; then
        echo "Removing stale/partially patched LLVM source tree..."
        rm -rf "$SRC"
    fi
fi

echo "Building LLD with the complete Mogrix IRIX patch set..."
bash "$CANONICAL"

if [[ ! -x "$BUILT" ]]; then
    echo "ERROR: canonical build did not produce $BUILT" >&2
    exit 1
fi

sudo mkdir -p "$DEST_DIR"
sudo cp "$BUILT" "$DEST_DIR/ld.lld-irix-18"
sudo chmod 0755 "$DEST_DIR/ld.lld-irix-18"
sudo ln -sfn ld.lld-irix-18 "$DEST_DIR/ld.lld-irix"

echo "Verifying IRIX emulation support..."
if ! "$DEST_DIR/ld.lld-irix" -m elf32btsmipn32_irix --version >/dev/null; then
    echo "ERROR: rebuilt LLD still does not accept elf32btsmipn32_irix" >&2
    exit 1
fi

echo "Installed fully patched LLD: $DEST_DIR/ld.lld-irix-18"
echo "IRIX emulation check: OK"
