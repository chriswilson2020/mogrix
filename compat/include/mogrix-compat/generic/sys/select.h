/*
 * mogrix-compat/generic/sys/select.h
 *
 * Wrapper that includes the real sys/select.h and adds pselect()
 * declaration for IRIX compatibility.
 *
 * IRIX has select() but lacks pselect() (POSIX.1-2001).
 * The implementation (compat/stdlib/pselect.c) wraps select()
 * with sigprocmask().
 *
 * Do not include <sys/time.h> here.  On IRIX, <sys/types.h> pulls in
 * <sys/bsd_types.h>, which in turn includes <sys/select.h>.  Including
 * <sys/time.h> from this wrapper re-enters that chain before fd_set has been
 * completed and leaves sys/time.h seeing an unknown fd_set.  pselect only uses
 * struct timespec through a pointer, so a forward declaration is sufficient.
 */

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
