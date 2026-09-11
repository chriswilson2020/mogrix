/*
 * mogrix-compat/generic/sys/select.h
 *
 * Wrapper that includes the real sys/select.h and adds pselect()
 * declaration for IRIX compatibility.
 *
 * IRIX 6.5 has a special recursive include path:
 *   sys/timespec.h -> sys/types.h -> sys/bsd_types.h -> sys/select.h
 *
 * During that path fd_set is not complete yet.  In that state this wrapper
 * must do exactly what gnulib does for IRIX: delegate to the system header and
 * add no declarations.  A later normal inclusion of <sys/select.h> then enters
 * the full wrapper and adds pselect().
 */

#if defined(__sgi) && defined(_SYS_BSD_TYPES_H) \
    && !defined(_MOGRIX_SYS_SELECT_REDIRECT_FROM_BSD_TYPES_H)

#define _MOGRIX_SYS_SELECT_REDIRECT_FROM_BSD_TYPES_H 1
#include_next <sys/select.h>

#else

#ifndef _MOGRIX_COMPAT_SYS_SELECT_H
#define _MOGRIX_COMPAT_SYS_SELECT_H

#include_next <sys/select.h>
#include <signal.h>

struct timespec;

#ifdef __cplusplus
extern "C" {
#endif

int pselect(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds,
            const struct timespec *timeout, const sigset_t *sigmask);

#ifdef __cplusplus
}
#endif

#endif /* _MOGRIX_COMPAT_SYS_SELECT_H */

#endif /* IRIX sys/bsd_types.h redirect */
