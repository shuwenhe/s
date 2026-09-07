#ifndef S_COMPILER_RUNTIME_H
#define S_COMPILER_RUNTIME_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

/* Host allocator boundary for the S ownership backend. No object registry,
   tracing, root scanning, write barriers or reference counting is involved. */
#ifdef S_COMPILER_CHECK_ALLOCATIONS
static int64_t compiler_objects;
#endif
static inline void compiler_trap(const char *message) {
    fprintf(stderr, "compiler runtime: %s\n", message);
    exit(70);
}
static inline int64_t compiler_live(void) {
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    return compiler_objects;
#else
    compiler_trap("live_allocations requires S_COMPILER_CHECK_ALLOCATIONS");
    return 0;
#endif
}
static inline int64_t *compiler_box(int64_t value) {
    int64_t *p = (int64_t *)malloc(sizeof(*p));
    if (!p) compiler_trap("allocation failed");
    *p = value;
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    ++compiler_objects;
#endif
    return p;
}
static inline int64_t *compiler_move(int64_t **source) {
    int64_t *p = *source;
    *source = NULL;
    return p;
}
static inline void compiler_drop(int64_t **owner);
typedef struct compiler_pair {
    int64_t *left;
    int64_t *right;
} compiler_pair;
static inline compiler_pair *compiler_pair_make(int64_t *left, int64_t *right) {
    compiler_pair *p = (compiler_pair *)malloc(sizeof(*p));
    if (!p) compiler_trap("allocation failed");
    p->left = left;
    p->right = right;
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    ++compiler_objects;
#endif
    return p;
}
static inline compiler_pair *compiler_pair_move(compiler_pair **source) {
    compiler_pair *p = *source;
    *source = NULL;
    return p;
}
static inline int64_t *compiler_pair_move_field(compiler_pair *p, int field) {
    int64_t **slot = field == 0 ? &p->left : &p->right;
    return compiler_move(slot);
}
static inline void compiler_pair_drop(compiler_pair **owner) {
    if (*owner) {
        compiler_drop(&(*owner)->left);
        compiler_drop(&(*owner)->right);
        free(*owner);
        *owner = NULL;
#ifdef S_COMPILER_CHECK_ALLOCATIONS
        --compiler_objects;
#endif
    }
}
static inline void compiler_drop(int64_t **owner) {
    if (*owner) {
        free(*owner);
        *owner = NULL;
#ifdef S_COMPILER_CHECK_ALLOCATIONS
        --compiler_objects;
#endif
    }
}
static inline int compiler_finish(int64_t result) {
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    if (compiler_objects != 0) compiler_trap("live allocations at normal exit");
#endif
    return (int)((uint64_t)result & UINT64_C(255));
}
static inline void compiler_assert(int64_t condition) {
    if (!condition) compiler_trap("assertion failed");
}
static inline int64_t compiler_add(int64_t a, int64_t b) {
    int64_t r;
    if (__builtin_add_overflow(a, b, &r)) compiler_trap("integer overflow");
    return r;
}
static inline int64_t compiler_sub(int64_t a, int64_t b) {
    int64_t r;
    if (__builtin_sub_overflow(a, b, &r)) compiler_trap("integer overflow");
    return r;
}
static inline int64_t compiler_mul(int64_t a, int64_t b) {
    int64_t r;
    if (__builtin_mul_overflow(a, b, &r)) compiler_trap("integer overflow");
    return r;
}
static inline int64_t compiler_div(int64_t a, int64_t b) {
    if (!b || (a == INT64_MIN && b == -1)) compiler_trap("invalid division");
    return a / b;
}
static inline int64_t compiler_mod(int64_t a, int64_t b) {
    if (!b || (a == INT64_MIN && b == -1)) compiler_trap("invalid remainder");
    return a % b;
}
#endif
