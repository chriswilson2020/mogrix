#include <stdio.h>

/*
 * Exercise the exported libatomic entry points directly so this test cannot be
 * optimized into inline LL/SC sequences by Clang.  In particular, the sized
 * compare-exchange ABI includes the 'weak' argument before the two memory
 * orders; omitting it shifts the calling convention and corrupts the call.
 */
extern unsigned long long __atomic_load_8(const volatile void *, int);
extern void __atomic_store_8(volatile void *, unsigned long long, int);
extern unsigned long long __atomic_fetch_add_8(volatile void *, unsigned long long, int);
extern int __atomic_compare_exchange_8(volatile void *, void *, unsigned long long,
                                       int, int, int);

int main(void)
{
    volatile unsigned long long value = 4;
    unsigned long long expected = 7;
    unsigned long long old;

    __atomic_store_8(&value, 7ULL, __ATOMIC_SEQ_CST);
    if (__atomic_load_8(&value, __ATOMIC_SEQ_CST) != 7ULL)
        return 2;

    old = __atomic_fetch_add_8(&value, 2ULL, __ATOMIC_SEQ_CST);
    if (old != 7ULL || value != 9ULL)
        return 3;

    expected = 9ULL;
    if (!__atomic_compare_exchange_8(&value, &expected, 13ULL, 0,
                                     __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
        return 4;
    if (value != 13ULL)
        return 5;

    puts("mogrix libatomic ABI OK");
    return 0;
}
