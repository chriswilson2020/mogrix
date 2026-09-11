/*
 * Legacy compatibility archive for the old Mogrix bootstrap path.
 *
 * Current Mogrix ships cross/lib32/libgcc_s.so.1, built from LLVM
 * compiler-rt builtins plus GCC unwind support.  That runtime contains the
 * MIPS N32 soft-float helpers, including the 128-bit/long-double (__*tf*)
 * entry points.  Executables and shared libraries therefore link libgcc_s;
 * this translation unit intentionally provides no compiler runtime symbols.
 *
 * It remains only so older staging/bootstrap code that insists on creating
 * libsoft_float_stubs.a can do so without carrying a second, divergent copy
 * of the compiler runtime implementations.
 */

int __mogrix_legacy_soft_float_stubs_archive;
