#!/bin/bash
# Install the GCC 9.5 libstdc++ headers expected by cross/bin/irix-cxx.
#
# GCC's libstdc++ source tree is not laid out like the installed include tree:
# public headers are split across include/std, include/c_global and several
# subdirectories.  This script reconstructs the installed-style tree and then
# overlays Mogrix's tracked IRIX-specific files.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${SGUG_STAGING:-/opt/sgug-staging/usr/sgug}"
CACHE="${MOGRIX_GCC_CACHE:-$ROOT/cross/build-runtime/gcc-9.5.0}"
GCC_URL="${MOGRIX_GCC_URL:-https://ftp.gnu.org/gnu/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz}"
INCLUDE_SRC="$CACHE/libstdc++-v3/include"
DEST="$STAGING/include/c++/9"

have_source_tree() {
    [[ -f "$INCLUDE_SRC/std/vector" && \
       -f "$INCLUDE_SRC/std/stdexcept" && \
       -f "$INCLUDE_SRC/c_global/cstdio" ]]
}

if ! have_source_tree; then
    command -v curl >/dev/null 2>&1 || {
        echo "ERROR: curl is required to obtain GCC 9.5.0 headers" >&2
        exit 1
    }
    command -v tar >/dev/null 2>&1 || {
        echo "ERROR: tar is required to extract GCC 9.5.0 headers" >&2
        exit 1
    }

    echo "GCC 9.5.0 libstdc++ headers are not cached; downloading source..."
    mkdir -p "$(dirname "$CACHE")"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    curl -fL "$GCC_URL" -o "$tmp/gcc-9.5.0.tar.xz"
    rm -rf "$CACHE/libstdc++-v3/include"
    tar -xJf "$tmp/gcc-9.5.0.tar.xz" \
        -C "$(dirname "$CACHE")" \
        "gcc-9.5.0/libstdc++-v3/include"
fi

if ! have_source_tree; then
    echo "ERROR: GCC header source is incomplete: $INCLUDE_SRC" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"

# Installed libstdc++ puts the contents of include/std and include/c_global at
# the top level of <c++/9>, while the supporting directories remain directories.
cp -R "$INCLUDE_SRC/std"/. "$DEST"/
cp -R "$INCLUDE_SRC/c_global"/. "$DEST"/

for dir in bits backward decimal experimental ext parallel profile tr1; do
    if [[ -d "$INCLUDE_SRC/$dir" ]]; then
        cp -R "$INCLUDE_SRC/$dir" "$DEST/$dir"
    fi
done

# Overlay the files Mogrix intentionally tracks for the IRIX target, including
# target bits/c++config.h and local header fixes such as ext/string_conversions.h.
if [[ -d "$ROOT/cross/include/c++/9" ]]; then
    cp -R "$ROOT/cross/include/c++/9"/. "$DEST"/
fi

for header in cstdio stdexcept vector string; do
    if [[ ! -f "$DEST/$header" ]]; then
        echo "ERROR: missing installed libstdc++ header: $DEST/$header" >&2
        exit 1
    fi
done

if [[ ! -f "$DEST/mips-sgi-irix6.5/bits/c++config.h" ]]; then
    echo "ERROR: IRIX target c++config.h was not installed" >&2
    exit 1
fi

echo "Installed GCC 9.5.0 libstdc++ headers to $DEST"
