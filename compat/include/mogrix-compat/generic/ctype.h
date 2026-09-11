#ifndef MOGRIX_COMPAT_GENERIC_CTYPE_H
#define MOGRIX_COMPAT_GENERIC_CTYPE_H

/* Pull in the native IRIX ctype declarations first. */
#include_next <ctype.h>

/* IRIX 6.5 predates C99's isblank(), but GCC 9's <cctype> expects it in the
 * global namespace when its C99 ctype support is enabled.  Keep this as a
 * header-only compatibility shim so C and C++ callers see the standard
 * semantics without adding another runtime symbol. */
#ifndef isblank
static __inline__ int
isblank(int c)
{
    return c == ' ' || c == '\t';
}
#endif

#endif /* MOGRIX_COMPAT_GENERIC_CTYPE_H */
