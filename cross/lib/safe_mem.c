/*
 * Byte-safe memory/string routines for IRIX.
 *
 * Some optimized IRIX libc/libstdc++ routines perform aligned word reads past
 * the logical end of a buffer.  That is normally harmless, but can SIGSEGV at
 * a page boundary.  These implementations deliberately read one byte at a
 * time.  The std::_Hash_bytes entry point uses the 32-bit MurmurHash2 variant
 * used by libstdc++ on 32-bit targets, but also performs only byte reads.
 *
 * This file is freestanding on purpose: build-runtime-objects.sh compiles it
 * with raw clang rather than irix-cc.
 */

typedef __SIZE_TYPE__ size_t;

typedef unsigned char u8;

int memcmp(const void *lhs, const void *rhs, size_t n)
{
    const u8 *a = (const u8 *)lhs;
    const u8 *b = (const u8 *)rhs;
    size_t i;

    for (i = 0; i < n; ++i) {
        if (a[i] != b[i])
            return (int)a[i] - (int)b[i];
    }
    return 0;
}

int strcmp(const char *lhs, const char *rhs)
{
    const u8 *a = (const u8 *)lhs;
    const u8 *b = (const u8 *)rhs;

    while (*a && *a == *b) {
        ++a;
        ++b;
    }
    return (int)*a - (int)*b;
}

int strncmp(const char *lhs, const char *rhs, size_t n)
{
    const u8 *a = (const u8 *)lhs;
    const u8 *b = (const u8 *)rhs;
    size_t i;

    for (i = 0; i < n; ++i) {
        if (a[i] != b[i])
            return (int)a[i] - (int)b[i];
        if (a[i] == 0)
            return 0;
    }
    return 0;
}

/* libstdc++ symbol: std::_Hash_bytes(void const*, size_t, size_t). */
size_t mogrix_hash_bytes(const void *ptr, size_t len, size_t seed)
    __asm__("_ZSt11_Hash_bytesPKvmm");

size_t mogrix_hash_bytes(const void *ptr, size_t len, size_t seed)
{
    const u8 *data = (const u8 *)ptr;
    const size_t m = (size_t)0x5bd1e995U;
    size_t h = seed ^ len;

    while (len >= 4) {
        size_t k = (size_t)data[0]
                 | ((size_t)data[1] << 8)
                 | ((size_t)data[2] << 16)
                 | ((size_t)data[3] << 24);

        k *= m;
        k ^= k >> 24;
        k *= m;
        h *= m;
        h ^= k;

        data += 4;
        len -= 4;
    }

    switch (len) {
    case 3:
        h ^= (size_t)data[2] << 16;
        /* fall through */
    case 2:
        h ^= (size_t)data[1] << 8;
        /* fall through */
    case 1:
        h ^= (size_t)data[0];
        h *= m;
        break;
    default:
        break;
    }

    h ^= h >> 13;
    h *= m;
    h ^= h >> 15;
    return h;
}
