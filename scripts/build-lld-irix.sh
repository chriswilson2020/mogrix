#!/bin/bash
# Build the fully patched LLVM 18 LLD required by Mogrix/IRIX.
#
# IMPORTANT: the canonical patch logic lives in lld-fixes/build-lld-irix.sh.
# This wrapper also applies the IRIX InputFiles compatibility fix that the
# canonical builder documents but currently does not apply itself.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT/tmp/lld-irix-build"
SRC="$BUILD_ROOT/llvm-project-18.1.3.src"
DRIVER="$SRC/lld/ELF/Driver.cpp"
INPUTFILES="$SRC/lld/ELF/InputFiles.cpp"
CANONICAL="$ROOT/lld-fixes/build-lld-irix.sh"
BUILT="$ROOT/tools/bin/ld.lld-irix-18"
DEST_DIR="/opt/cross/bin"

if [[ ! -f "$CANONICAL" ]]; then
    echo "ERROR: canonical LLD builder missing: $CANONICAL" >&2
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

if [[ ! -f "$INPUTFILES" ]]; then
    echo "ERROR: LLVM InputFiles.cpp not found after canonical build" >&2
    exit 1
fi

# IRIX DSOs such as libpthread.so contain local section symbols (.text, .data,
# .rel.dyn, etc.) in the global part of the symbol table. Stock LLD rejects
# that layout. Apply the same logic as lld-fixes/02-inputfiles-... but do it via
# an exact source transformation because that historical patch file has a bad
# hunk header and GNU patch rejects it as malformed.
if ! grep -q 'IRIX shared libraries violate this' "$INPUTFILES"; then
    echo "Applying IRIX MIPS shared-library symbol-table compatibility fix..."
    python3 - "$INPUTFILES" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
old = '''    StringRef name = CHECK(sym.getName(stringTable), this);\n    if (sym.getBinding() == STB_LOCAL) {\n      errorOrWarn(toString(this) + ": invalid local symbol '" + name +\n                  "' in global part of symbol table");\n      continue;\n    }\n'''
new = '''    StringRef name = CHECK(sym.getName(stringTable), this);\n    if (sym.getBinding() == STB_LOCAL) {\n      // IRIX shared libraries violate the usual ELF symbol ordering and place\n      // local section symbols such as .text/.data in the global part of the\n      // symbol table. IRIX DSOs use OSABI 0, so key this exception to MIPS and\n      // section-style names rather than ELFOSABI_IRIX.\n      if (emachine != EM_MIPS || !name.starts_with("."))\n        errorOrWarn(toString(this) + ": invalid local symbol '" + name +\n                    "' in global part of symbol table");\n      continue;\n    }\n'''
if old not in s:
    raise SystemExit("ERROR: expected LLVM 18 SharedFile::parse local-symbol block not found")
p.write_text(s.replace(old, new, 1))
PY

    echo "Incrementally rebuilding LLD after InputFiles fix..."
    ninja -C "$SRC/build" lld
    cp "$SRC/build/bin/lld" "$BUILT"
    chmod +x "$BUILT"
else
    echo "IRIX MIPS shared-library symbol-table compatibility fix already present."
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
