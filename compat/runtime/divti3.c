/*
 * 128-bit integer division helpers for MIPS n32.
 *
 * These mirror the compiler-rt/libgcc entry points without using native
 * 128-bit division (which would recursively call the same helpers).
 */

typedef __int128 ti_int;
typedef unsigned __int128 tu_int;

static tu_int mogrix_udivmodti4(tu_int num, tu_int den, tu_int *rem)
{
    tu_int q = 0;
    tu_int r = 0;
    int bit;

    if (den == 0)
        __builtin_trap();

    for (bit = 127; bit >= 0; --bit) {
        r = (r << 1) | ((num >> bit) & (tu_int)1);
        if (r >= den) {
            r -= den;
            q |= (tu_int)1 << bit;
        }
    }

    if (rem)
        *rem = r;
    return q;
}

tu_int __udivti3(tu_int a, tu_int b)
{
    return mogrix_udivmodti4(a, b, (tu_int *)0);
}

tu_int __umodti3(tu_int a, tu_int b)
{
    tu_int r;
    (void)mogrix_udivmodti4(a, b, &r);
    return r;
}

static tu_int mogrix_abs_ti(ti_int v)
{
    if (v >= 0)
        return (tu_int)v;
    /* Avoid signed overflow for INT128_MIN. */
    return (tu_int)(-(v + 1)) + 1;
}

ti_int __divti3(ti_int a, ti_int b)
{
    int neg;
    tu_int ua;
    tu_int ub;
    tu_int q;

    if (b == 0)
        __builtin_trap();

    neg = (a < 0) ^ (b < 0);
    ua = mogrix_abs_ti(a);
    ub = mogrix_abs_ti(b);
    q = mogrix_udivmodti4(ua, ub, (tu_int *)0);

    if (!neg)
        return (ti_int)q;

    /* q may be 2^127 for INT128_MIN / 1. */
    if (q == ((tu_int)1 << 127))
        return (ti_int)((tu_int)1 << 127);
    return -(ti_int)q;
}

ti_int __modti3(ti_int a, ti_int b)
{
    tu_int ua;
    tu_int ub;
    tu_int r;

    if (b == 0)
        __builtin_trap();

    ua = mogrix_abs_ti(a);
    ub = mogrix_abs_ti(b);
    (void)mogrix_udivmodti4(ua, ub, &r);

    if (a < 0 && r != 0)
        return -(ti_int)r;
    return (ti_int)r;
}
