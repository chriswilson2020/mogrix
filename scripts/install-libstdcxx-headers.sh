#!/bin/bash
# Install the GCC 9.5 libstdc++ headers expected by cross/bin/irix-cxx.
#
# The repository tracks IRIX-specific overrides/configuration under
# cross/include/c++/9, but not the complete generic GCC libstdc++ header set.
# A clean checkout therefore lacks fundamental headers such as <cstdio> and
# <stdexcept>.  This script obtains the matching GCC 9.5.0 source headers and
# overlays Mogrix's tracked IRIX-specific files on top.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${SGUG_STAGING:-/opt/sgug-staging/usr/sgug}"
CACHE="${MOGRIX_GCC_CACHE:-$ROOT/cross/build-runtime/gcc-9.5.0}"
GCC_URL="${MOGRIX_GCC_URL:-https://ftp.gnu.org/gnu/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz}"
GENERIC_HEADERS="$CACHE/libstdc++-v3/include"
DEST="$STAGING/include/c++/9"

if [[ ! -d "$GENERIC_HEADERS" ]]; then
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
    tar -xJf "$tmp/gcc-9.5.0.tar.xz" \
        -C "$(dirname "$CACHE")" \
        --strip-components=0 \
        "gcc-9.5.0/libstdc++-v3/include"
fi

if [[ ! -f "$GENERIC_HEADERS/cstdio" || ! -f "$GENERIC_HEADERS/stdexcept" ]]; then
    echo "ERROR: GCC header source is incomplete: $GENERIC_HEADERS" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$GENERIC_HEADERS"/. "$DEST"/

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
