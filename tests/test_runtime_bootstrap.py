"""Regression tests for the cross-runtime bootstrap layout.

These tests deliberately avoid requiring an IRIX sysroot or cross compiler. They
catch the repository-level failures that made a clean checkout non-reproducible:
missing runtime sources, stale soft-float staging requirements, linker drift,
and losing the real C++ wrapper during setup.
"""

from pathlib import Path

from mogrix.staging import StagingManager


ROOT = Path(__file__).resolve().parents[1]


def test_required_runtime_sources_are_tracked() -> None:
    required = [
        ROOT / "cross/lib/dso_handle.c",
        ROOT / "cross/lib/safe_mem.c",
        ROOT / "compat/runtime/libatomic_stub.c",
        ROOT / "compat/runtime/muloti4.c",
        ROOT / "compat/runtime/divti3.c",
        ROOT / "cross/irix-shared.lds",
        ROOT / "cross/bin/irix-cxx",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    assert not missing, f"missing tracked runtime sources: {missing}"


def test_staging_uses_current_runtime_model() -> None:
    assert "libsoft_float_stubs.a" not in StagingManager.REQUIRED_LIBS
    assert "soft_float_stubs.c" not in StagingManager.RUNTIME_SOURCES
    assert StagingManager.RUNTIME_SOURCES["libatomic_stub.c"] == "libatomic.a"


def test_executable_linker_uses_libgcc_runtime() -> None:
    linker = (ROOT / "cross/bin/irix-ld").read_text()
    assert "-lsoft_float_stubs" not in linker
    assert 'LIBGCC_S_FLAG="-lgcc_s -lpthread"' in linker


def test_real_cxx_wrapper_recognizes_cpp_sources() -> None:
    cxx = (ROOT / "cross/bin/irix-cxx").read_text()
    assert "clang++" in cxx
    assert "*.cpp|*.cxx|*.cc|*.C" in cxx


def test_bootstrap_predeploys_real_cxx_wrapper() -> None:
    bootstrap = (ROOT / "scripts/bootstrap-cross.sh").read_text()
    assert 'cross/bin/irix-cxx' in bootstrap
    assert 'install -m 0755' in bootstrap


def test_safe_hash_preserves_big_endian_n32_word_order() -> None:
    safe_mem = (ROOT / "cross/lib/safe_mem.c").read_text()
    assert "((size_t)data[0] << 24)" in safe_mem
    assert "((size_t)data[1] << 16)" in safe_mem
    assert "((size_t)data[2] << 8)" in safe_mem
