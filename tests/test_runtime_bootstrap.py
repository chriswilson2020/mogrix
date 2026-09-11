"""Regression tests for the cross-runtime bootstrap layout.

These tests deliberately avoid requiring an IRIX sysroot or cross compiler. They
catch the repository-level failures that made a clean checkout non-reproducible:
missing runtime sources, stale soft-float staging requirements, linker drift,
and losing the real C++ wrapper/headers during setup.
"""

from pathlib import Path

from mogrix.staging import StagingManager


ROOT = Path(__file__).resolve().parents[1]


def test_required_runtime_sources_are_tracked() -> None:
    required = [
        ROOT / "cross/lib/dso_handle.c",
        ROOT / "cross/lib/safe_mem.c",
        ROOT / "cross/crt/eh_frame_reg.c",
        ROOT / "compat/runtime/libatomic_stub.c",
        ROOT / "compat/runtime/muloti4.c",
        ROOT / "compat/runtime/divti3.c",
        ROOT / "compat/runtime/stpcpy.c",
        ROOT / "compat/runtime/stpncpy.c",
        ROOT / "compat/runtime/spawn.c",
        ROOT / "cross/irix-shared.lds",
        ROOT / "cross/bin/irix-cxx",
        ROOT / "cross/include/c++/9/mips-sgi-irix6.5/bits/c++config.h",
        ROOT / "scripts/install-libstdcxx-headers.sh",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.exists()]
    assert not missing, f"missing tracked runtime sources: {missing}"


def test_staging_uses_current_runtime_model() -> None:
    assert "libsoft_float_stubs.a" not in StagingManager.REQUIRED_LIBS
    assert "soft_float_stubs.c" not in StagingManager.RUNTIME_SOURCES
    assert StagingManager.RUNTIME_SOURCES["libatomic_stub.c"] == "libatomic.a"


def test_executable_linker_uses_libgcc_runtime() -> None:
    linker = (ROOT / "cross/bin/irix-ld").read_text()
    assert "-lsoft_float_stubs" not in linker
    assert 'LIBGCC_S_FLAG="-lgcc_s -lpthread"' in linker
    assert '/home/edodd/' not in linker
    assert 'IRIX_LLD:-/opt/cross/bin/ld.lld-irix' in linker


def test_runtime_builder_matches_linker_requirements() -> None:
    builder = (ROOT / "scripts/build-runtime-objects.sh").read_text()
    assert "eh_frame_reg.o" in builder
    assert "dso_handle.o" in builder
    assert "safe_mem.o" in builder
    assert "dlmalloc.o" in builder
    assert "libatomic.a" in builder
    assert "libsoft_float_stubs.a" not in builder.split("EXPECTED=(", 1)[1]


def test_real_cxx_wrapper_recognizes_cpp_sources() -> None:
    cxx = (ROOT / "cross/bin/irix-cxx").read_text()
    assert "clang++" in cxx
    assert "*.cpp|*.cxx|*.cc|*.C" in cxx
    assert "$STAGING/include/c++/9" in cxx
    assert "$STAGING/include/c++/9/mips-sgi-irix6.5" in cxx


def test_clean_bootstrap_bypasses_legacy_setup_cross() -> None:
    bootstrap = (ROOT / "scripts/bootstrap-cross.sh").read_text()
    assert 'cross/bin/irix-cxx' in bootstrap
    assert 'install -m 0755' in bootstrap
    assert 'uv run mogrix setup-cross' not in bootstrap
    assert 'libsoft_float_stubs.a' not in bootstrap
    assert 'libgcc_s.so.1' in bootstrap
    assert 'install-libstdcxx-headers.sh' in bootstrap


def test_libstdcxx_header_installer_uses_matching_gcc_and_overlays_irix_config() -> None:
    installer = (ROOT / "scripts/install-libstdcxx-headers.sh").read_text()
    assert "gcc-9.5.0.tar.xz" in installer
    assert "libstdc++-v3/include" in installer
    assert 'cross/include/c++/9' in installer
    assert 'mips-sgi-irix6.5/bits/c++config.h' in installer
    assert 'cstdio' in installer
    assert 'stdexcept' in installer


def test_safe_hash_preserves_big_endian_n32_word_order() -> None:
    safe_mem = (ROOT / "cross/lib/safe_mem.c").read_text()
    assert "((size_t)data[0] << 24)" in safe_mem
    assert "((size_t)data[1] << 16)" in safe_mem
    assert "((size_t)data[2] << 8)" in safe_mem


def test_libatomic_sized_compare_exchange_has_weak_parameter() -> None:
    atomic = (ROOT / "compat/runtime/libatomic_stub.c").read_text()
    assert "T d, int weak, int so, int fo" in atomic
    assert "(void)weak" in atomic


def test_direct_libatomic_abi_smoke_test_is_built() -> None:
    script = (ROOT / "scripts/test-cross-runtime.sh").read_text()
    assert "tests/runtime/atomic_abi.c" in script
    assert "-latomic" in script
