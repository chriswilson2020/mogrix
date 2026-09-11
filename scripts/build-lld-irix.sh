#!/bin/bash
# Build the fully patched LLVM 18 LLD required by Mogrix/IRIX.
#
# IMPORTANT: the canonical patch logic lives in lld-fixes/build-lld-irix.sh.
# This wrapper also applies the IRIX InputFiles compatibility patch that the
# canonical builder documents but currently does not apply itself.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT/tmp/lld-irix-build"
SRC="$BUILD_ROOT/llvm-project-18.1.3.src"
DRIVER="$SRC/lld/ELF/Driver.cpp"
INPUTFILES="$SRC/lld/ELF/InputFiles.cpp"
CANONICAL="$ROOT/lld-fixes/build-lld-irix.sh"
INPUT_PATCH="$ROOT/lld-fixes/02-inputfiles-mips-local-symbols.patch"
BUILT="$ROOT/tools/bin/ld.lld-irix-18"
DEST_DIR="/opt/cross/bin"

if [[ ! -f "$CANONICAL" ]]; then
    echo "ERROR: canonical LLD builder missing: $CANONICAL" >&2
    exit 1
fi
if [[ ! -f "$INPUT_PATCH" ]]; then
    echo "ERROR: IRIX InputFiles patch missing: $INPUT_PATCH" >&2
    exit 1
fi

# A source tree touched by the historical partial builder contains the Writer
# patch but not the Driver.cpp `_irix` emulation support. Re-extract from the
# cached tarball in that case. The source tarball itself is kept.
if [[ -d "$SRC" ]]; then
    if [[ ! -f "$DRIVER" ]] || ! grep -q 'ends_with("_irix")' "$DRIVER"; then
        echo "Removing stale/partially patched LLVM source tree..."
        rm -rf "$SRC"
    fi
fi

# Let the canonical builder create/patch/build the tree first. On an existing
# fully configured tree this is incremental.
echo "Building LLD with the Mogrix IRIX patch set..."
bash "$CANONICAL"

# The canonical script's README includes this patch, but its apply_patches()
# implementation currently does not apply it. IRIX DSOs such as libpthread.so
# contain local section symbols (.text, .data, .rel.dyn, etc.) in the global
# part of the symbol table, which stock LLD rejects. Apply it idempotently and
# rebuild only the affected LLD object plus relink.
if [[ ! -f "$INPUTFILES" ]]; then
    echo "ERROR: LLVM InputFiles.cpp not found after canonical build" >&2
    exit 1
fi

if grep -q 'invalid local symbol' "$INPUTFILES" && ! grep -q 'emachine != EM_MIPS.*name.starts_with' "$INPUTFILES"; then
    echo "Applying IRIX MIPS shared-library symbol-table compatibility patch..."
    (
        cd "$SRC"
        patch -p1 < "$INPUT_PATCH"
    )

    echo "Incrementally rebuilding LLD after InputFiles patch..."
    ninja -C "$SRC/build" lld
    cp "$SRC/build/bin/lld" "$BUILT"
    chmod +x "$BUILT"
else
    echo "IRIX MIPS shared-library symbol-table compatibility patch already present."
fi

if [[ ! -x "$BUILT" ]]; then
    echo "ERROR: build did not produce $BUILT" >&2
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
