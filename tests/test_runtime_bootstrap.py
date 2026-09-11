"""Regression tests for the cross-runtime bootstrap layout.

These tests deliberately avoid requiring an IRIX sysroot or cross compiler. They
catch the repository-level failures that made a clean checkout non-reproducible:
missing runtime sources, stale soft-float staging requirements, and linker drift.
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
