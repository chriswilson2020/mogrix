#!/bin/bash
# build-runtime-objects.sh — build/deploy the runtime objects required by irix-ld

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOGRIX_DIR="$(dirname "$SCRIPT_DIR")"
STAGING="${SGUG_STAGING:-/opt/sgug-staging/usr/sgug}"
SYSROOT="${IRIX_SYSROOT:-/opt/irix-sysroot}"
CROSS="${IRIX_CROSS_BINDIR:-/opt/cross/bin}"
CC="${STAGING}/bin/irix-cc"
AR="${CROSS}/llvm-ar"
RAW_CLANG="${CROSS}/clang"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
PASS=0
FAIL=0
TOTAL=0

log_ok()   { echo -e "  ${GREEN}[OK]${NC} $*"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $*"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
log_info() { echo -e "  ${YELLOW}[..]${NC} $*"; }

need_exec() {
    if [[ ! -x "$1" ]]; then
        echo -e "${RED}ERROR:${NC} missing executable: $1" >&2
        exit 1
    fi
}

need_exec "$CC"
need_exec "$AR"
need_exec "$RAW_CLANG"
mkdir -p "$STAGING/lib32"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

RUNTIME_INC="${MOGRIX_DIR}/compat/include/mogrix-compat/generic"

# Runtime compatibility implementations must compile against the *native* IRIX
# declarations first.  The public Mogrix wrapper headers intentionally shadow
# libc headers for package builds, but using those wrappers while building the
# wrappers' own implementation creates recursive/include-order failures on IRIX
# (fd_set during sys/bsd_types.h, and then missing libc/socket declarations).
# Put the sysroot headers first and make the Mogrix generic directory an
# -idirafter fallback: native headers win when IRIX has one, while missing
# headers such as <spawn.h> are still supplied by Mogrix.
RUNTIME_CFLAGS=(
    --target=mips-sgi-irix6.5
    --sysroot="$SYSROOT"
    -mabi=n32
    -march=mips3
    -mxgot
    -fno-stack-protector
    -U_MIPS_ISA
    -D_MIPS_ISA=_MIPS_ISA_MIPS3
    -D_SGI_SOURCE
    -D_SGI_MP_SOURCE
    -D_SGI_REENTRANT_FUNCTIONS
    -Dsgi=1
    -D__sgi=1
    -D_COMPILER_VERSION=730
    -D_LANGUAGE_C=1
    -D_LONGLONG=1
    -Dunix=1
    -D__unix__=1
    -D__unix=1
    -isystem "$SYSROOT/usr/include"
    -idirafter "$RUNTIME_INC"
)

echo "=== Mogrix Runtime Objects Builder ==="
echo "Sources:  $MOGRIX_DIR"
echo "Staging:  $STAGING/lib32"
echo

build_obj() {
    local name="$1"
    local src="$2"
    shift 2
    if "$CC" "$@" -c "$src" -o "$TMPDIR/$name" 2>"$TMPDIR/$name.err"; then
        cp "$TMPDIR/$name" "$STAGING/lib32/$name"
        log_ok "$name"
    else
        log_fail "$name"
        cat "$TMPDIR/$name.err" >&2 || true
    fi
}

build_runtime_obj() {
    local name="$1"
    local src="$2"
    shift 2
    if "$RAW_CLANG" "${RUNTIME_CFLAGS[@]}" "$@" -c "$src" \
        -o "$TMPDIR/$name" 2>"$TMPDIR/$name.err"; then
        return 0
    fi
    cat "$TMPDIR/$name.err" >&2 || true
    return 1
}

echo "[1/6] CRT and exception-registration objects..."
build_obj crtbeginS.o "$MOGRIX_DIR/cross/crt/crtbeginS.S" -fPIC
build_obj crtendS.o   "$MOGRIX_DIR/cross/crt/crtendS.S" -fPIC
build_obj crtbeginT.o "$MOGRIX_DIR/cross/crt/crtbeginT.S"
build_obj crtendT.o   "$MOGRIX_DIR/cross/crt/crtendT.S"
build_obj eh_frame_reg.o "$MOGRIX_DIR/cross/crt/eh_frame_reg.c" -fPIC

echo
echo "[2/6] Linker support objects..."
build_obj dso_handle.o "$MOGRIX_DIR/cross/lib/dso_handle.c" -fPIC

# safe_mem.c is intentionally freestanding so it cannot pick up optimized libc
# declarations/implementations that reintroduce the page-boundary over-read.
if "$RAW_CLANG" --target=mips-sgi-irix6.5 -mabi=n32 -march=mips3 -fPIC -w \
    -c "$MOGRIX_DIR/cross/lib/safe_mem.c" -o "$TMPDIR/safe_mem.o" \
    2>"$TMPDIR/safe_mem.o.err"; then
    cp "$TMPDIR/safe_mem.o" "$STAGING/lib32/safe_mem.o"
    log_ok safe_mem.o
else
    log_fail safe_mem.o
    cat "$TMPDIR/safe_mem.o.err" >&2 || true
fi

echo
echo "[3/6] dlmalloc..."
if "$CC" -c -O2 \
    -DHAVE_MORECORE=0 -DHAVE_MMAP=1 \
    -DUSE_LOCKS=1 -DUSE_SPIN_LOCKS=1 \
    -DMMAP_CLEARS=1 -Dmalloc_getpagesize=16384 \
    "$MOGRIX_DIR/compat/malloc/dlmalloc.c" -o "$TMPDIR/dlmalloc.o" \
    2>"$TMPDIR/dlmalloc.o.err"; then
    cp "$TMPDIR/dlmalloc.o" "$STAGING/lib32/dlmalloc.o"
    log_ok dlmalloc.o
else
    log_fail dlmalloc.o
    cat "$TMPDIR/dlmalloc.o.err" >&2 || true
fi

echo
echo "[4/6] Static compatibility archives..."

# libatomic is still required by packages that cause Clang to emit out-of-line
# __atomic_* calls. It is independent from the compiler builtins in libgcc_s.
if build_runtime_obj libatomic_stub.o "$MOGRIX_DIR/compat/runtime/libatomic_stub.c"; then
    "$AR" rcs "$STAGING/lib32/libatomic.a" "$TMPDIR/libatomic_stub.o"
    log_ok libatomic.a
else
    log_fail libatomic.a
fi

# The old libsoft_float_stubs.a is deliberately NOT built. Current Mogrix ships
# cross/lib32/libgcc_s.so.1, whose compiler-rt builtins provide the soft-float,
# quad-float and integer helper symbols for both executables and DSOs.

COMPAT_OBJS=()
compat_ok=true
shopt -s nullglob
for src in "$MOGRIX_DIR"/compat/runtime/*.c; do
    base=$(basename "$src" .c)
    case "$base" in
        libatomic_stub|soft_float_stubs) continue ;;
    esac
    obj="$TMPDIR/${base}.o"
    if build_runtime_obj "${base}.o" "$src"; then
        COMPAT_OBJS+=("$obj")
    else
        log_fail "libcompat.a (${base}.c)"
        compat_ok=false
    fi
done
shopt -u nullglob

if [[ ${#COMPAT_OBJS[@]} -gt 0 ]]; then
    "$AR" rcs "$STAGING/lib32/libcompat.a" "${COMPAT_OBJS[@]}"
    if $compat_ok; then
        log_ok libcompat.a
    else
        log_info "libcompat.a created from successful objects, but one or more sources failed"
    fi
else
    log_fail "libcompat.a (no runtime sources compiled)"
fi

echo
echo "[5/6] libmogrix_compat.so..."
COMPAT_SO_SRCS=()
for rel in \
    compat/stdlib/bsearch.c \
    compat/sys/socketpair.c \
    compat/sys/shm_open.c \
    compat/sys/mincore.c \
    compat/runtime/muloti4.c \
    compat/runtime/divti3.c \
    compat/stdlib/mkdtemp.c \
    compat/error/strerror_r.c \
    compat/string/memmem.c \
    patches/shared/mogrix_crash_handler.c
do
    src="$MOGRIX_DIR/$rel"
    if [[ -f "$src" ]]; then
        COMPAT_SO_SRCS+=("$src")
    else
        log_fail "libmogrix_compat.so (missing $rel)"
    fi
done

# Compile each implementation with native IRIX headers first, then pass only
# objects to irix-cc for the shared-library link.  This keeps package-facing
# wrapper headers out of the implementation build while preserving the custom
# IRIX linker/CRT path.
COMPAT_SO_OBJS=()
compat_so_compile_ok=true
for src in "${COMPAT_SO_SRCS[@]}"; do
    base=$(basename "$src" .c)
    obj="$TMPDIR/compat-so-${base}.o"
    if build_runtime_obj "compat-so-${base}.o" "$src" -fPIC \
        -I"$MOGRIX_DIR/patches/shared"; then
        COMPAT_SO_OBJS+=("$obj")
    else
        log_fail "libmogrix_compat.so (compile $(basename "$src"))"
        compat_so_compile_ok=false
    fi
done

if $compat_so_compile_ok && [[ ${#COMPAT_SO_OBJS[@]} -gt 0 ]]; then
    if "$CC" -shared "${COMPAT_SO_OBJS[@]}" \
        -o "$TMPDIR/libmogrix_compat.so" \
        2>"$TMPDIR/libmogrix_compat.so.err"; then
        cp "$TMPDIR/libmogrix_compat.so" "$STAGING/lib32/libmogrix_compat.so"
        log_ok libmogrix_compat.so
    else
        log_fail "libmogrix_compat.so (link failed)"
        cat "$TMPDIR/libmogrix_compat.so.err" >&2 || true
    fi
fi

echo
echo "[6/6] Linker and CRT metadata..."
if [[ -f "$MOGRIX_DIR/cross/irix-shared.lds" ]]; then
    cp "$MOGRIX_DIR/cross/irix-shared.lds" "$STAGING/lib32/irix-shared.lds"
    log_ok irix-shared.lds
else
    log_fail "irix-shared.lds (source missing)"
fi

if [[ -f "$MOGRIX_DIR/cross/crt/crt-hide.ver" ]]; then
    cp "$MOGRIX_DIR/cross/crt/crt-hide.ver" "$STAGING/lib32/crt-hide.ver"
    log_ok crt-hide.ver
else
    log_fail "crt-hide.ver (source missing)"
fi

echo
echo "=== Results ==="
echo "  Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo

EXPECTED=(
    crtbeginS.o crtendS.o crtbeginT.o crtendT.o eh_frame_reg.o
    dso_handle.o safe_mem.o dlmalloc.o
    libatomic.a libcompat.a libmogrix_compat.so
    irix-shared.lds crt-hide.ver
)
missing=0
for f in "${EXPECTED[@]}"; do
    if [[ -f "$STAGING/lib32/$f" ]]; then
        size=$(stat -c%s "$STAGING/lib32/$f" 2>/dev/null || echo '?')
        echo -e "  ${GREEN}OK${NC}  $f  ($size bytes)"
    else
        echo -e "  ${RED}MISSING${NC}  $f"
        missing=$((missing + 1))
    fi
done

if [[ $FAIL -eq 0 && $missing -eq 0 ]]; then
    echo
    echo -e "${GREEN}All required runtime objects built and deployed.${NC}"
else
    echo
    echo -e "${YELLOW}Runtime bootstrap incomplete; inspect failures above.${NC}"
    exit 1
fi
