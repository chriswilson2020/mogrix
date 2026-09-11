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

/* N32 is unusual: pointers are 32-bit, but GPRs and _Unwind_Word are 64-bit.
   GCC's unwinder therefore must keep register values in _Unwind_Word-sized
   context slots rather than void * slots.  Without this, by-value register
   state is truncated to 32 bits while walking a frame. */
#define REG_VALUE_IN_UNWIND_CONTEXT 1
#define ASSUME_EXTENDED_UNWIND_CONTEXT 1

/* Clang's MIPS __unwind_word__ mode is 64-bit for N32, and clang emits sd/ld
   saves for the integer GPRs.  The DWARF size table must describe those saved
   slots as 8 bytes.  This includes $gp (r28), $fp (r30), and $ra (r31); leaving
   $gp at 4 bytes on big-endian IRIX reads the zero high half and breaks the
   following unwind step.  Keep non-GPR entries at the conservative 4-byte
   baseline until target-specific FP/pseudo-register CFI requires otherwise. */
#define __builtin_init_dwarf_reg_size_table(TABLE) do { \
    int __mogrix_i; \
    for (__mogrix_i = 0; __mogrix_i < __LIBGCC_DWARF_FRAME_REGISTERS__ + 1; ++__mogrix_i) \
        (TABLE)[__mogrix_i] = 4; \
    for (__mogrix_i = 0; __mogrix_i < 32; ++__mogrix_i) \
        (TABLE)[__mogrix_i] = 8; \
} while (0)

/* GCC's machine word/register width for MIPS N32 is 64-bit. */
#define __LIBGCC_UNITS_PER_WORD__ 8

#endif /* GCC_TCONFIG_H */
