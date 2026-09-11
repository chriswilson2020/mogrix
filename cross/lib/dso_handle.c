/*
 * Mogrix IRIX runtime support: __dso_handle
 *
 * __cxa_atexit() uses this token to associate destructors with the
 * executable/DSO that registered them.  GCC's crtbegin normally provides
 * the symbol; Mogrix uses custom CRT objects, so provide it explicitly.
 */

void *__dso_handle = &__dso_handle;
