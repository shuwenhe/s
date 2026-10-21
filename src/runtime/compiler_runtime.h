#ifndef S_COMPILER_RUNTIME_H
#define S_COMPILER_RUNTIME_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>



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
static inline int64_t compiler_index(int64_t length, int64_t index) {
    if (index < 0 || index >= length) compiler_trap("array index out of bounds");
    return index;
}
typedef struct compiler_array {
    void *data;
    int64_t len;
    size_t element_size;
    const char *element_type;
    void (*destroy_element)(void *);
    int copyable;
} compiler_array;
static inline compiler_array *compiler_array_new(int64_t count, size_t size,
        const char *type, const void *initial, void (*destroy)(void *), int copyable) {
    if (count < 0) compiler_trap("negative array length");
    if (size == 0 || (uint64_t)count > SIZE_MAX / size)
        compiler_trap("array allocation size overflow");
    compiler_array *array = (compiler_array *)malloc(sizeof(*array));
    if (!array) compiler_trap("allocation failed");
    array->data = calloc(count ? (size_t)count : 1, size);
    if (!array->data) { free(array); compiler_trap("allocation failed"); }
    array->len = count;
    array->element_size = size;
    array->element_type = type;
    array->destroy_element = destroy;
    array->copyable = copyable;
    if (initial) {
        for (int64_t i = 0; i < count; ++i)
            memcpy((char *)array->data + (size_t)i * size, initial, size);
    }
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    compiler_objects += 2;
#endif
    return array;
}
static inline void *compiler_array_at(compiler_array *array, int64_t index) {
    if (!array) compiler_trap("access to moved array");
    return (char *)array->data + (size_t)compiler_index(array->len, index) * array->element_size;
}
static inline void *compiler_array_copy_element(compiler_array *array, int64_t index) {
    if (!array->copyable) compiler_trap("array element is not copyable");
    const void *source = compiler_array_at(array, index);
    void *value = malloc(array->element_size);
    if (!value) compiler_trap("allocation failed");
    memcpy(value, source, array->element_size);
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    ++compiler_objects;
#endif
    return value;
}
static inline void compiler_array_store_record(compiler_array *array, int64_t index, void *value) {
    void *target = compiler_array_at(array, index);
    if (!value) compiler_trap("move from null record");
    if (array->destroy_element) array->destroy_element(target);
    memcpy(target, value, array->element_size);
    free(value);
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    --compiler_objects;
#endif
}
static inline void compiler_array_copy(compiler_array *target, compiler_array *source, int64_t count) {
    if (!target || !source) compiler_trap("access to moved array");
    if (target->element_size != source->element_size || strcmp(target->element_type, source->element_type))
        compiler_trap("array copy element type mismatch");
    if (!target->copyable || !source->copyable) compiler_trap("array element is not copyable");
    if (count < 0 || count > target->len || count > source->len)
        compiler_trap("array copy out of bounds");
    memmove(target->data, source->data, (size_t)count * target->element_size);
}
static inline compiler_array *compiler_array_move(compiler_array **source) {
    compiler_array *array = *source;
    *source = NULL;
    return array;
}
static inline void compiler_array_drop(compiler_array **owner) {
    if (*owner) {
        compiler_array *array = *owner;
        if (array->destroy_element) {
            for (int64_t i = 0; i < array->len; ++i)
                array->destroy_element((char *)array->data + (size_t)i * array->element_size);
        }
        free(array->data);
        free(array);
        *owner = NULL;
#ifdef S_COMPILER_CHECK_ALLOCATIONS
        compiler_objects -= 2;
#endif
    }
}

typedef struct compiler_slice {
    int64_t *data;
    int64_t len;
} compiler_slice;
static inline compiler_slice *compiler_slice_from_array(const int64_t *source, int64_t len) {
    compiler_slice *slice = (compiler_slice *)malloc(sizeof(*slice));
    if (!slice) compiler_trap("allocation failed");
    slice->data = (int64_t *)malloc((size_t)len * sizeof(*slice->data));
    if (!slice->data) compiler_trap("allocation failed");
    for (int64_t i = 0; i < len; ++i) slice->data[i] = source[i];
    slice->len = len;
#ifdef S_COMPILER_CHECK_ALLOCATIONS
    compiler_objects += 2;
#endif
    return slice;
}
static inline compiler_slice *compiler_slice_move(compiler_slice **source) {
    compiler_slice *slice = *source;
    *source = NULL;
    return slice;
}
static inline void compiler_slice_drop(compiler_slice **owner) {
    if (*owner) {
        free((*owner)->data);
        free(*owner);
        *owner = NULL;
#ifdef S_COMPILER_CHECK_ALLOCATIONS
        compiler_objects -= 2;
#endif
    }
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
        compiler_drop(&(*owner)->right);
        compiler_drop(&(*owner)->left);
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
