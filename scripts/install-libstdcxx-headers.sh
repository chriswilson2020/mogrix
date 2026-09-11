#!/bin/bash
# Install the GCC 9.5 libstdc++ headers expected by cross/bin/irix-cxx.
#
# GCC's libstdc++ source tree is not laid out like the installed include tree:
# public headers are split across include/std, include/c_global and several
# subdirectories; libsupc++ contributes both top-level and bits/ headers; and
# configure-selected host headers such as bits/c++allocator.h, bits/c++io.h,
# and locale support headers come from libstdc++-v3/config.
# This script reconstructs the installed-style tree and then overlays Mogrix's
# tracked IRIX-specific files.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${SGUG_STAGING:-/opt/sgug-staging/usr/sgug}"
CACHE="${MOGRIX_GCC_CACHE:-$ROOT/cross/build-runtime/gcc-9.5.0}"
GCC_URL="${MOGRIX_GCC_URL:-https://ftp.gnu.org/gnu/gcc/gcc-9.5.0/gcc-9.5.0.tar.xz}"
INCLUDE_SRC="$CACHE/libstdc++-v3/include"
CONFIG_SRC="$CACHE/libstdc++-v3/config"
SUPCXX_SRC="$CACHE/libstdc++-v3/libsupc++"
DEST="$STAGING/include/c++/9"
TARGET_BITS="$DEST/mips-sgi-irix6.5/bits"

have_public_headers() {
    [[ -f "$INCLUDE_SRC/std/vector" && \
       -f "$INCLUDE_SRC/std/stdexcept" && \
       -f "$INCLUDE_SRC/c_global/cstdio" && \
       -f "$INCLUDE_SRC/pstl/pstl_config.h" && \
       -f "$INCLUDE_SRC/debug/assertions.h" ]]
}

have_support_headers() {
    [[ -f "$CONFIG_SRC/os/generic/os_defines.h" && \
       -f "$CONFIG_SRC/cpu/generic/cpu_defines.h" && \
       -f "$CONFIG_SRC/cpu/generic/cxxabi_tweaks.h" && \
       -f "$CONFIG_SRC/cpu/generic/atomic_word.h" && \
       -f "$CONFIG_SRC/cpu/generic/atomicity_builtins/atomicity.h" && \
       -f "$CONFIG_SRC/os/generic/error_constants.h" && \
       -f "$CONFIG_SRC/allocator/new_allocator_base.h" && \
       -f "$CONFIG_SRC/io/c_io_stdio.h" && \
       -f "$CONFIG_SRC/io/basic_file_stdio.h" && \
       -f "$CONFIG_SRC/locale/generic/c_locale.h" && \
       -f "$CONFIG_SRC/locale/generic/messages_members.h" && \
       -f "$CONFIG_SRC/locale/generic/time_members.h" ]]
}

have_supcxx_headers() {
    [[ -f "$SUPCXX_SRC/exception_defines.h" && \
       -f "$SUPCXX_SRC/exception" && \
       -f "$SUPCXX_SRC/new" && \
       -f "$SUPCXX_SRC/typeinfo" && \
       -f "$SUPCXX_SRC/cxxabi.h" ]]
}

fetch_needed_source() {
    command -v curl >/dev/null 2>&1 || {
        echo "ERROR: curl is required to obtain GCC 9.5.0 headers" >&2
        exit 1
    }
    command -v tar >/dev/null 2>&1 || {
        echo "ERROR: tar is required to extract GCC 9.5.0 headers" >&2
        exit 1
    }

    echo "GCC 9.5.0 libstdc++ header sources are incomplete; downloading source..."
    mkdir -p "$(dirname "$CACHE")"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    curl -fL "$GCC_URL" -o "$tmp/gcc-9.5.0.tar.xz"

    if ! have_public_headers; then
        rm -rf "$CACHE/libstdc++-v3/include"
        tar -xJf "$tmp/gcc-9.5.0.tar.xz" \
            -C "$(dirname "$CACHE")" \
            "gcc-9.5.0/libstdc++-v3/include"
    fi

    if ! have_support_headers; then
        rm -rf "$CONFIG_SRC/os/generic" "$CONFIG_SRC/cpu/generic" \
               "$CONFIG_SRC/allocator" "$CONFIG_SRC/io" \
               "$CONFIG_SRC/locale/generic"
        tar -xJf "$tmp/gcc-9.5.0.tar.xz" \
            -C "$(dirname "$CACHE")" \
            "gcc-9.5.0/libstdc++-v3/config/os/generic" \
            "gcc-9.5.0/libstdc++-v3/config/cpu/generic" \
            "gcc-9.5.0/libstdc++-v3/config/allocator" \
            "gcc-9.5.0/libstdc++-v3/config/io" \
            "gcc-9.5.0/libstdc++-v3/config/locale/generic"
    fi

    if ! have_supcxx_headers; then
        rm -rf "$SUPCXX_SRC"
        tar -xJf "$tmp/gcc-9.5.0.tar.xz" \
            -C "$(dirname "$CACHE")" \
            "gcc-9.5.0/libstdc++-v3/libsupc++"
    fi
}

if ! have_public_headers || ! have_support_headers || ! have_supcxx_headers; then
    fetch_needed_source
fi

if ! have_public_headers; then
    echo "ERROR: GCC public header source is incomplete: $INCLUDE_SRC" >&2
    exit 1
fi
if ! have_support_headers; then
    echo "ERROR: GCC target-support header source is incomplete: $CONFIG_SRC" >&2
    exit 1
fi
if ! have_supcxx_headers; then
    echo "ERROR: GCC libsupc++ header source is incomplete: $SUPCXX_SRC" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"

# Installed libstdc++ puts the contents of include/std and include/c_global at
# the top level of <c++/9>, while supporting include subdirectories remain
# subdirectories. Keep this list aligned with GCC's installed header layout.
cp -R "$INCLUDE_SRC/std"/. "$DEST"/
cp -R "$INCLUDE_SRC/c_global"/. "$DEST"/

for dir in bits backward debug decimal experimental ext parallel profile tr1 pstl; do
    if [[ -d "$INCLUDE_SRC/$dir" ]]; then
        cp -R "$INCLUDE_SRC/$dir" "$DEST/$dir"
    fi
done

# libsupc++ contributes installed C++ ABI/exception headers.
for header in cxxabi.h exception initializer_list new typeinfo; do
    install -m 0644 "$SUPCXX_SRC/$header" "$DEST/$header"
done
mkdir -p "$DEST/bits"
for header in atomic_lockfree_defines.h cxxabi_forced.h exception_defines.h \
              exception_ptr.h hash_bytes.h nested_exception.h exception.h \
              cxxabi_init_exception.h; do
    install -m 0644 "$SUPCXX_SRC/$header" "$DEST/bits/$header"
done

# GCC's installed tree also contains configure-selected host headers under
# bits/.  Reconstruct the standard generic choices used by Mogrix's GCC 9
# runtime rather than discovering these one missing include at a time.
install -m 0644 "$CONFIG_SRC/allocator/new_allocator_base.h" \
    "$DEST/bits/c++allocator.h"
install -m 0644 "$CONFIG_SRC/io/c_io_stdio.h" \
    "$DEST/bits/c++io.h"
install -m 0644 "$CONFIG_SRC/io/basic_file_stdio.h" \
    "$DEST/bits/basic_file.h"
install -m 0644 "$CONFIG_SRC/locale/generic/c_locale.h" \
    "$DEST/bits/c++locale.h"
install -m 0644 "$CONFIG_SRC/locale/generic/messages_members.h" \
    "$DEST/bits/messages_members.h"
install -m 0644 "$CONFIG_SRC/locale/generic/time_members.h" \
    "$DEST/bits/time_members.h"

# Overlay the files Mogrix intentionally tracks for the IRIX target, including
# the configured target bits/c++config.h and local fixes.
if [[ -d "$ROOT/cross/include/c++/9" ]]; then
    cp -R "$ROOT/cross/include/c++/9"/. "$DEST"/
fi

# Target-specific selected support headers live below the GCC target include
# directory. GCC 9 no longer carries an IRIX OS directory, so use its generic
# OS/CPU support around Mogrix's already configured IRIX c++config.h.
mkdir -p "$TARGET_BITS"
install -m 0644 "$CONFIG_SRC/os/generic/os_defines.h" \
    "$TARGET_BITS/os_defines.h"
install -m 0644 "$CONFIG_SRC/cpu/generic/cpu_defines.h" \
    "$TARGET_BITS/cpu_defines.h"
install -m 0644 "$CONFIG_SRC/cpu/generic/cxxabi_tweaks.h" \
    "$TARGET_BITS/cxxabi_tweaks.h"
install -m 0644 "$CONFIG_SRC/cpu/generic/atomic_word.h" \
    "$TARGET_BITS/atomic_word.h"
install -m 0644 "$CONFIG_SRC/cpu/generic/atomicity_builtins/atomicity.h" \
    "$TARGET_BITS/atomicity.h"
install -m 0644 "$CONFIG_SRC/os/generic/error_constants.h" \
    "$TARGET_BITS/error_constants.h"

for header in cstdio stdexcept vector string exception new typeinfo cxxabi.h; do
    if [[ ! -f "$DEST/$header" ]]; then
        echo "ERROR: missing installed libstdc++ header: $DEST/$header" >&2
        exit 1
    fi
done

for header in pstl/pstl_config.h debug/assertions.h; do
    if [[ ! -f "$DEST/$header" ]]; then
        echo "ERROR: missing installed libstdc++ support header: $DEST/$header" >&2
        exit 1
    fi
done

for header in exception_defines.h exception_ptr.h hash_bytes.h nested_exception.h exception.h \
              c++allocator.h c++io.h basic_file.h c++locale.h messages_members.h time_members.h; do
    if [[ ! -f "$DEST/bits/$header" ]]; then
        echo "ERROR: missing installed libstdc++ bits header: $DEST/bits/$header" >&2
        exit 1
    fi
done

for header in c++config.h os_defines.h cpu_defines.h cxxabi_tweaks.h atomic_word.h atomicity.h error_constants.h; do
    if [[ ! -f "$TARGET_BITS/$header" ]]; then
        echo "ERROR: missing target libstdc++ support header: $TARGET_BITS/$header" >&2
        exit 1
    fi
done

echo "Installed GCC 9.5.0 libstdc++ headers to $DEST"
