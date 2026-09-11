/* POSIX.1-2008 stpcpy compatibility for IRIX. */

char *stpcpy(char *dst, const char *src)
{
    while ((*dst = *src) != '\0') {
        ++dst;
        ++src;
    }
    return dst;
}
