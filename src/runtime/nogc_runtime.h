#ifndef S_NOGC_RUNTIME_H
#define S_NOGC_RUNTIME_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

/* Host allocator boundary for the S ownership backend. No object registry,
   tracing, root scanning, write barriers or reference counting is involved. */
#ifdef S_NOGC_CHECK_ALLOCATIONS
static int64_t ng_objects;
#endif
static inline void ng_trap(const char *message) {
    fprintf(stderr, "nogc runtime: %s\n", message);
    exit(70);
}
static inline int64_t ng_live(void) {
#ifdef S_NOGC_CHECK_ALLOCATIONS
    return ng_objects;
#else
    ng_trap("live_allocations requires S_NOGC_CHECK_ALLOCATIONS");
    return 0;
#endif
}
static inline int64_t *ng_box(int64_t value) {
    int64_t *p = (int64_t *)malloc(sizeof(*p));
    if (!p) ng_trap("allocation failed");
    *p = value;
#ifdef S_NOGC_CHECK_ALLOCATIONS
    ++ng_objects;
#endif
    return p;
}
static inline int64_t *ng_move(int64_t **source) {
    int64_t *p = *source;
    *source = NULL;
    return p;
}
static inline void ng_drop(int64_t **owner) {
    if (*owner) {
        free(*owner);
        *owner = NULL;
#ifdef S_NOGC_CHECK_ALLOCATIONS
        --ng_objects;
#endif
    }
}
static inline int ng_finish(int64_t result) {
#ifdef S_NOGC_CHECK_ALLOCATIONS
    if (ng_objects != 0) ng_trap("live allocations at normal exit");
#endif
    return (int)((uint64_t)result & UINT64_C(255));
}
static inline void ng_assert(int64_t condition) {
    if (!condition) ng_trap("assertion failed");
}
static inline int64_t ng_add(int64_t a, int64_t b) {
    int64_t r;
    if (__builtin_add_overflow(a, b, &r)) ng_trap("integer overflow");
    return r;
}
static inline int64_t ng_sub(int64_t a, int64_t b) {
    int64_t r;
    if (__builtin_sub_overflow(a, b, &r)) ng_trap("integer overflow");
    return r;
}
static inline int64_t ng_mul(int64_t a, int64_t b) {
    int64_t r;
    if (__builtin_mul_overflow(a, b, &r)) ng_trap("integer overflow");
    return r;
}
static inline int64_t ng_div(int64_t a, int64_t b) {
    if (!b || (a == INT64_MIN && b == -1)) ng_trap("invalid division");
    return a / b;
}
static inline int64_t ng_mod(int64_t a, int64_t b) {
    if (!b || (a == INT64_MIN && b == -1)) ng_trap("invalid remainder");
    return a % b;
}
#endif
