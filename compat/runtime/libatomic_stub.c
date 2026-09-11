/*
 * Small libatomic compatibility layer for IRIX/MIPS n32.
 *
 * Correctness is preferred over lock-free performance: operations are
 * serialized by one process-wide spin lock. This supplies the libatomic ABI
 * expected by software compiled with Clang when an operation is not emitted
 * inline for the target. Memory-order arguments are accepted but the global
 * lock provides stronger (sequentially consistent) ordering.
 */

typedef __SIZE_TYPE__ size_t;
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;

static volatile u32 mogrix_atomic_lock_word;

static void mogrix_atomic_lock(void)
{
    while (__sync_lock_test_and_set(&mogrix_atomic_lock_word, 1U)) {
        while (mogrix_atomic_lock_word)
            ;
    }
    __sync_synchronize();
}

static void mogrix_atomic_unlock(void)
{
    __sync_synchronize();
    __sync_lock_release(&mogrix_atomic_lock_word);
}

static void byte_copy(void *dst_, const void *src_, size_t n)
{
    volatile u8 *dst = (volatile u8 *)dst_;
    const volatile u8 *src = (const volatile u8 *)src_;
    size_t i;
    for (i = 0; i < n; ++i)
        dst[i] = src[i];
}

static int byte_equal(const void *a_, const void *b_, size_t n)
{
    const volatile u8 *a = (const volatile u8 *)a_;
    const volatile u8 *b = (const volatile u8 *)b_;
    size_t i;
    for (i = 0; i < n; ++i)
        if (a[i] != b[i])
            return 0;
    return 1;
}

void mogrix_atomic_load(size_t n, const volatile void *mem, void *ret, int order)
    __asm__("__atomic_load");
void mogrix_atomic_store(size_t n, volatile void *mem, const void *val, int order)
    __asm__("__atomic_store");
void mogrix_atomic_exchange(size_t n, volatile void *mem, const void *val, void *ret, int order)
    __asm__("__atomic_exchange");
int mogrix_atomic_compare_exchange(size_t n, volatile void *mem, void *expected,
                                   const void *desired, int success_order,
                                   int failure_order)
    __asm__("__atomic_compare_exchange");
int mogrix_atomic_is_lock_free(size_t n, const volatile void *mem)
    __asm__("__atomic_is_lock_free");
void mogrix_atomic_thread_fence(int order) __asm__("__atomic_thread_fence");
void mogrix_atomic_signal_fence(int order) __asm__("__atomic_signal_fence");
int mogrix_atomic_test_and_set(volatile void *mem, int order)
    __asm__("__atomic_test_and_set");
void mogrix_atomic_clear(volatile void *mem, int order)
    __asm__("__atomic_clear");

void mogrix_atomic_load(size_t n, const volatile void *mem, void *ret, int order)
{
    (void)order;
    mogrix_atomic_lock();
    byte_copy(ret, (const void *)mem, n);
    mogrix_atomic_unlock();
}

void mogrix_atomic_store(size_t n, volatile void *mem, const void *val, int order)
{
    (void)order;
    mogrix_atomic_lock();
    byte_copy((void *)mem, val, n);
    mogrix_atomic_unlock();
}

void mogrix_atomic_exchange(size_t n, volatile void *mem, const void *val, void *ret, int order)
{
    (void)order;
    mogrix_atomic_lock();
    byte_copy(ret, (const void *)mem, n);
    byte_copy((void *)mem, val, n);
    mogrix_atomic_unlock();
}

int mogrix_atomic_compare_exchange(size_t n, volatile void *mem, void *expected,
                                   const void *desired, int success_order,
                                   int failure_order)
{
    int equal;
    (void)success_order;
    (void)failure_order;
    mogrix_atomic_lock();
    equal = byte_equal((const void *)mem, expected, n);
    if (equal)
        byte_copy((void *)mem, desired, n);
    else
        byte_copy(expected, (const void *)mem, n);
    mogrix_atomic_unlock();
    return equal;
}

int mogrix_atomic_is_lock_free(size_t n, const volatile void *mem)
{
    (void)n;
    (void)mem;
    return 0;
}

void mogrix_atomic_thread_fence(int order)
{
    (void)order;
    __sync_synchronize();
}

void mogrix_atomic_signal_fence(int order)
{
    (void)order;
    __asm__ __volatile__("" ::: "memory");
}

int mogrix_atomic_test_and_set(volatile void *mem, int order)
{
    u8 one = 1;
    u8 old;
    mogrix_atomic_exchange(1, mem, &one, &old, order);
    return old != 0;
}

void mogrix_atomic_clear(volatile void *mem, int order)
{
    u8 zero = 0;
    mogrix_atomic_store(1, mem, &zero, order);
}

#define DECL_LOAD_STORE(N, T) \
T mogrix_atomic_load_##N(const volatile void *, int) __asm__("__atomic_load_" #N); \
void mogrix_atomic_store_##N(volatile void *, T, int) __asm__("__atomic_store_" #N); \
T mogrix_atomic_exchange_##N(volatile void *, T, int) __asm__("__atomic_exchange_" #N); \
int mogrix_atomic_compare_exchange_##N(volatile void *, void *, T, int, int) \
    __asm__("__atomic_compare_exchange_" #N); \
T mogrix_atomic_load_##N(const volatile void *p, int o) \
{ T v; mogrix_atomic_load(sizeof(T), p, &v, o); return v; } \
void mogrix_atomic_store_##N(volatile void *p, T v, int o) \
{ mogrix_atomic_store(sizeof(T), p, &v, o); } \
T mogrix_atomic_exchange_##N(volatile void *p, T v, int o) \
{ T old; mogrix_atomic_exchange(sizeof(T), p, &v, &old, o); return old; } \
int mogrix_atomic_compare_exchange_##N(volatile void *p, void *e, T d, int so, int fo) \
{ return mogrix_atomic_compare_exchange(sizeof(T), p, e, &d, so, fo); }

DECL_LOAD_STORE(1, u8)
DECL_LOAD_STORE(2, u16)
DECL_LOAD_STORE(4, u32)
DECL_LOAD_STORE(8, u64)

#define DECL_FETCH_OP(N, T, NAME, OP) \
T mogrix_atomic_fetch_##NAME##_##N(volatile void *, T, int) \
    __asm__("__atomic_fetch_" #NAME "_" #N); \
T mogrix_atomic_##NAME##_fetch_##N(volatile void *, T, int) \
    __asm__("__atomic_" #NAME "_fetch_" #N); \
T mogrix_atomic_fetch_##NAME##_##N(volatile void *p, T v, int o) \
{ T old, next; (void)o; mogrix_atomic_lock(); byte_copy(&old, (const void *)p, sizeof(T)); \
  next = (T)(old OP v); byte_copy((void *)p, &next, sizeof(T)); mogrix_atomic_unlock(); return old; } \
T mogrix_atomic_##NAME##_fetch_##N(volatile void *p, T v, int o) \
{ T old, next; (void)o; mogrix_atomic_lock(); byte_copy(&old, (const void *)p, sizeof(T)); \
  next = (T)(old OP v); byte_copy((void *)p, &next, sizeof(T)); mogrix_atomic_unlock(); return next; }

#define DECL_FETCH_NAND(N, T) \
T mogrix_atomic_fetch_nand_##N(volatile void *, T, int) \
    __asm__("__atomic_fetch_nand_" #N); \
T mogrix_atomic_nand_fetch_##N(volatile void *, T, int) \
    __asm__("__atomic_nand_fetch_" #N); \
T mogrix_atomic_fetch_nand_##N(volatile void *p, T v, int o) \
{ T old, next; (void)o; mogrix_atomic_lock(); byte_copy(&old, (const void *)p, sizeof(T)); \
  next = (T)(~(old & v)); byte_copy((void *)p, &next, sizeof(T)); mogrix_atomic_unlock(); return old; } \
T mogrix_atomic_nand_fetch_##N(volatile void *p, T v, int o) \
{ T old, next; (void)o; mogrix_atomic_lock(); byte_copy(&old, (const void *)p, sizeof(T)); \
  next = (T)(~(old & v)); byte_copy((void *)p, &next, sizeof(T)); mogrix_atomic_unlock(); return next; }

#define DECL_FETCH_SET(N, T) \
DECL_FETCH_OP(N, T, add, +) \
DECL_FETCH_OP(N, T, sub, -) \
DECL_FETCH_OP(N, T, and, &) \
DECL_FETCH_OP(N, T, or, |) \
DECL_FETCH_OP(N, T, xor, ^) \
DECL_FETCH_NAND(N, T)

DECL_FETCH_SET(1, u8)
DECL_FETCH_SET(2, u16)
DECL_FETCH_SET(4, u32)
DECL_FETCH_SET(8, u64)
