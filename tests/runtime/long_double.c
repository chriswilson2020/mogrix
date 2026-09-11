#include <stdio.h>

int main(void)
{
    volatile long double a = 1.25L;
    volatile long double b = 2.5L;
    volatile long double c = (a * b) + (b / a) - 0.5L;
    double out = (double)c;
    printf("mogrix long double OK: %.6f\n", out);
    return (out > 4.62 && out < 4.63) ? 0 : 3;
}
