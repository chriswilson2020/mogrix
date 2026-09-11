/*
 * 128-bit signed multiply-with-overflow helper for MIPS n32.
 */

typedef __int128 ti_int;
typedef unsigned __int128 tu_int;

extern tu_int __udivti3(tu_int, tu_int);

static tu_int mogrix_abs_ti(ti_int v)
{
    if (v >= 0)
        return (tu_int)v;
    return (tu_int)(-(v + 1)) + 1;
}

ti_int __muloti4(ti_int a, ti_int b, int *overflow)
{
    const tu_int sign_bit = (tu_int)1 << 127;
    const tu_int pos_max = sign_bit - 1;
    int neg = (a < 0) ^ (b < 0);
    tu_int ua = mogrix_abs_ti(a);
    tu_int ub = mogrix_abs_ti(b);
    tu_int limit = neg ? sign_bit : pos_max;
    tu_int product;

    *overflow = 0;

    if (ua != 0 && ub > __udivti3(limit, ua)) {
        *overflow = 1;
        /* Return the wrapped two's-complement product, matching compiler-rt. */
        product = ua * ub;
        if (neg)
            product = (tu_int)0 - product;
        return (ti_int)product;
    }

    product = ua * ub;
    if (!neg)
        return (ti_int)product;

    if (product == sign_bit)
        return (ti_int)sign_bit;
    return -(ti_int)product;
}
