#!/bin/bash
# Reproducible clean bootstrap for the Mogrix IRIX cross environment.
#
# This intentionally does not call `mogrix setup-cross`: current main checks for
# libsoft_float_stubs.a before deploying irix-cc and also synthesizes irix-cxx
# by copying the C wrapper.  Both behaviours are stale relative to the tracked
# libgcc_s runtime and the real cross/bin/irix-cxx wrapper.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${SGUG_STAGING:-/opt/sgug-staging/usr/sgug}"
STAGING_ROOT="$(dirname "$(dirname "$STAGING")")"
SYSROOT="${IRIX_SYSROOT:-/opt/irix-sysroot}"
CROSS="${IRIX_CROSS_BINDIR:-/opt/cross/bin}"

need_file() {
    if [[ ! -e "$1" ]]; then
        echo "ERROR: required file missing: $1" >&2
        exit 1
    fi
}

need_exec() {
    if [[ ! -x "$1" ]]; then
        echo "ERROR: required executable missing: $1" >&2
        exit 1
    fi
}

need_file "$SYSROOT/usr/include/stdio.h"
need_file "$SYSROOT/usr/lib32/libc.so"
need_exec "$CROSS/clang"
need_exec "$CROSS/ld.lld-irix"
need_exec "$CROSS/llvm-ar"

mkdir -p \
    "$STAGING/bin" \
    "$STAGING/include" \
    "$STAGING/lib32/pkgconfig" \
    "$STAGING_ROOT/usr"

install_tool() {
    local name="$1"
    if [[ -f "$ROOT/cross/bin/$name" ]]; then
        install -m 0755 "$ROOT/cross/bin/$name" "$STAGING/bin/$name"
        echo "  tool: $name"
    fi
}

echo "Deploying compiler/linker wrappers..."
for tool in \
    irix-cc irix-cxx irix-ld \
    fix-anon-relocs strip-verneed \
    irix-cxx-libcxx strip-eh-relocs
do
    install_tool "$tool"
done

if [[ -f "$ROOT/cross/bin/irix-cxx-restrict-fix.h" ]]; then
    install -m 0644 "$ROOT/cross/bin/irix-cxx-restrict-fix.h" \
        "$STAGING/bin/irix-cxx-restrict-fix.h"
fi

if [[ -f "$ROOT/cross/rpmmacros.irix" ]]; then
    install -m 0644 "$ROOT/cross/rpmmacros.irix" "$STAGING_ROOT/rpmmacros.irix"
fi

if [[ -f "$ROOT/cross/pkgconfig/pthread-stubs.pc" ]]; then
    install -m 0644 "$ROOT/cross/pkgconfig/pthread-stubs.pc" \
        "$STAGING/lib32/pkgconfig/pthread-stubs.pc"
fi

echo "Deploying tracked runtime libraries..."
for lib in libgcc_s.so.1 libstdc++.so.6 libc++.so.1 libc++abi.so.1; do
    if [[ -f "$ROOT/cross/lib32/$lib" ]]; then
        install -m 0644 "$ROOT/cross/lib32/$lib" "$STAGING/lib32/$lib"
        echo "  runtime: $lib"
    fi
done

link_runtime() {
    local target="$1"
    local link="$2"
    if [[ -e "$STAGING/lib32/$target" ]]; then
        ln -sfn "$target" "$STAGING/lib32/$link"
    fi
}
link_runtime libgcc_s.so.1 libgcc_s.so
link_runtime libstdc++.so.6 libstdc++.so
link_runtime libc++.so.1 libc++.so
link_runtime libc++abi.so.1 libc++abi.so

echo "Deploying compatibility headers..."
rm -rf "$STAGING/include/dicl-clang-compat" "$STAGING/include/mogrix-compat"
cp -R "$ROOT/cross/include/dicl-clang-compat" "$STAGING/include/dicl-clang-compat"
cp -R "$ROOT/compat/include/mogrix-compat" "$STAGING/include/mogrix-compat"
if [[ -f "$ROOT/cross/include/irix-compat.h" ]]; then
    install -m 0644 "$ROOT/cross/include/irix-compat.h" "$STAGING/include/irix-compat.h"
fi

# Only the IRIX-specific libstdc++ headers are tracked in the repository.  The
# generic GCC 9 headers (<cstdio>, <vector>, <stdexcept>, etc.) must come from
# matching GCC 9.5.0 source.  Install them, then overlay Mogrix's target fixes.
echo "Installing GCC 9.5.0 C++ headers..."
"$ROOT/scripts/install-libstdcxx-headers.sh"

link_sysroot_dir() {
    local target="$1"
    local link="$2"

    need_file "$target"
    if [[ -L "$link" ]]; then
        rm -f "$link"
    elif [[ -e "$link" ]]; then
        if [[ -d "$link" && -z "$(ls -A "$link" 2>/dev/null)" ]]; then
            rmdir "$link"
        else
            echo "ERROR: refusing to replace non-empty path: $link" >&2
            exit 1
        fi
    fi
    mkdir -p "$(dirname "$link")"
    ln -s "$target" "$link"
}

echo "Linking IRIX sysroot into staging..."
link_sysroot_dir "$SYSROOT/usr/include" "$STAGING_ROOT/usr/include"
link_sysroot_dir "$SYSROOT/usr/lib32" "$STAGING_ROOT/usr/lib32"
link_sysroot_dir "$SYSROOT/lib32" "$STAGING_ROOT/lib32"

echo "Building/deploying runtime objects..."
"$ROOT/scripts/build-runtime-objects.sh"

echo
echo "Bootstrap complete."
echo "C wrapper:   $STAGING/bin/irix-cc"
echo "C++ wrapper: $STAGING/bin/irix-cxx"
echo "Runtime:     $STAGING/lib32"
echo "Next:        $ROOT/scripts/test-cross-runtime.sh"
