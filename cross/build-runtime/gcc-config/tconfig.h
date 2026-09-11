/* Minimal tconfig.h for cross-compiling GCC unwind with clang for IRIX n32 */
#ifndef GCC_TCONFIG_H
#define GCC_TCONFIG_H

/* We're building libgcc, not using it */
#ifndef USED_FOR_TARGET
#define USED_FOR_TARGET
#endif

/* IRIX uses DWARF2 exceptions */
#define DWARF2_UNWIND_INFO 1

/* POSIX threads for thread-safe unwind */
#define SUPPORTS_WEAK 1
#define GTHREAD_USE_WEAK 1

/* Target: MIPS n32 */
#define __GCC_HAVE_DWARF2_CFI_ASM 1

/* MIPS register count: 188 pseudo-registers in GCC's MIPS backend.
   This defines the size of the DWARF register save arrays in unwind. */
#define FIRST_PSEUDO_REGISTER 188
#define __LIBGCC_DWARF_FRAME_REGISTERS__ FIRST_PSEUDO_REGISTER

/* Default: DWARF register numbers map directly to unwind columns */
#define DWARF_REG_TO_UNWIND_COLUMN(REGNO) (REGNO)

/* Stack grows downward on MIPS */
#define __LIBGCC_STACK_GROWS_DOWNWARD__ 1

/* MIPS return address is in $31 (ra) = DWARF register 31 */
#define DWARF_FRAME_RETURN_COLUMN 31
#define __LIBGCC_DWARF_FRAME_RETURN_COLUMN__ 31

/* DWARF CIE data alignment factor */
#define __LIBGCC_DWARF_CIE_DATA_ALIGNMENT__ -4

/* EH return data registers for MIPS (from gcc/config/mips/mips.h) */
#define __LIBGCC_EH_TABLES_CAN_BE_READ_ONLY__ 0
#define EH_RETURN_DATA_REGNO(N) ((N) < 4 ? (N) + 4 : INVALID_REGNUM)
#define INVALID_REGNUM (~(unsigned int)0)

/* N32 is ILP32 but uses 64-bit MIPS registers.  GCC's unwinder keeps a
   per-DWARF-register byte-size table and uses that table when loading saved
   registers from CFI locations.  Clang's generic MIPS implementation of
   __builtin_init_dwarf_reg_size_table() initializes MIPS registers as 4 bytes,
   which is wrong for N32: clang emits `sd`/`ld` saves for the 64-bit GPRs.
   On big-endian IRIX this makes libgcc read the high 32 bits of a saved GPR;
   for $ra that is normally zero, so the first unwind step produces IP=0.

   Override the clang builtin while compiling GCC's unwind-dw2.c.  The N32
   integer GPRs (0-31), FP registers (32-63), and HI/LO (64-65) are 64-bit.
   Leave the remaining pseudo/status registers zero-sized unless/until they are
   explicitly needed by CFI. */
#define __builtin_init_dwarf_reg_size_table(TABLE) do { \
    int __mogrix_i; \
    for (__mogrix_i = 0; __mogrix_i <= 65; ++__mogrix_i) \
        (TABLE)[__mogrix_i] = 8; \
} while (0)

/* N32 pointers are 32-bit, but the machine word/register width is 64-bit. */
#define __LIBGCC_UNITS_PER_WORD__ 8

#endif /* GCC_TCONFIG_H */
