/* POSIX.1-2008 stpncpy compatibility for IRIX. */

typedef __SIZE_TYPE__ size_t;

char *stpncpy(char *dst, const char *src, size_t n)
{
    char *out = dst;
    size_t i = 0;

    while (i < n && src[i] != '\0') {
        dst[i] = src[i];
        ++i;
    }

    out = dst + i;
    while (i < n) {
        dst[i] = '\0';
        ++i;
    }

    return out;
}
