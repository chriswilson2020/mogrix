#!/bin/bash
# Compile/link smoke tests for the reconstructed Mogrix runtime layer.
# Does not require access to an IRIX host; it verifies that the cross-toolchain
# can produce N32 MIPS executables for the runtime features we repaired.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="${SGUG_STAGING:-/opt/sgug-staging/usr/sgug}"
CC="$STAGING/bin/irix-cc"
CXX="$STAGING/bin/irix-cxx"
OUT="${1:-$ROOT/test-results/runtime-smoke}"

mkdir -p "$OUT"

for tool in "$CC" "$CXX"; do
    if [[ ! -x "$tool" ]]; then
        echo "ERROR: missing compiler wrapper: $tool" >&2
        exit 1
    fi
done

compile() {
    local label="$1"
    shift
    echo "==> $label"
    "$@"
    file "$OUT/$label"
    echo
}

compile hello \
    "$CC" "$ROOT/tests/runtime/hello.c" -o "$OUT/hello"

compile long_double \
    "$CC" "$ROOT/tests/runtime/long_double.c" -o "$OUT/long_double"

compile atomic_smoke \
    "$CC" "$ROOT/tests/runtime/atomic_smoke.c" -L"$STAGING/lib32" -latomic -o "$OUT/atomic_smoke"

compile hello_cpp \
    "$CXX" "$ROOT/tests/runtime/hello_cpp.cpp" -o "$OUT/hello_cpp"

echo "Built smoke-test executables in: $OUT"
echo "Expected file(1) class: ELF 32-bit MSB, MIPS N32, dynamically linked."
echo "Runtime execution on IRIX is still required before this repair is considered validated."
