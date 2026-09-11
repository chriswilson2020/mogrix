#include <stdio.h>

int main(void)
{
    volatile unsigned long long value = 1;
    unsigned long long old;
    unsigned long long expected;

    old = __atomic_fetch_add(&value, 2ULL, __ATOMIC_SEQ_CST);
    if (old != 1ULL || value != 3ULL)
        return 2;

    expected = 3ULL;
    if (!__atomic_compare_exchange_n(&value, &expected, 9ULL, 0,
                                     __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
        return 3;
    if (value != 9ULL)
        return 4;

    __atomic_store_n(&value, 11ULL, __ATOMIC_SEQ_CST);
    if (__atomic_load_n(&value, __ATOMIC_SEQ_CST) != 11ULL)
        return 5;

    puts("mogrix atomic runtime OK");
    return 0;
}
