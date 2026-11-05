#ifndef S_SEED_ARRAY_TYPE_H
#define S_SEED_ARRAY_TYPE_H
#include <ctype.h>
#include <stddef.h>
#include <string.h>

/* Legacy []T annotations are read at the boundary; new constructors emit T[]. */
static inline int seed_array_element(const char *type, char *out, size_t cap) {
    size_t len;
    const char *start = type;
    if (!type) return 0;
    len = strlen(type);
    if (len > 2 && type[len - 2] == '[' && type[len - 1] == ']') len -= 2;
    else if (len > 2 && type[0] == '[' && type[1] == ']') { start += 2; len -= 2; }
    else return 0;
    if (len + 1 > cap) return 0;
    memcpy(out, start, len);
    out[len] = '\0';
    return 1;
}

/* A concrete element may be a qualified generic record, including nested
 * dynamic arrays. Parse the shape rather than accepting arbitrary brackets. */
static inline int seed_array_type_parse(const char *type, size_t n, size_t *at, unsigned depth) {
    if (depth > 64 || *at >= n) return 0;
    if (*at + 1 < n && type[*at] == '(' && type[*at + 1] == ')') *at += 2;
    else {
        for (;;) {
            if (*at >= n || !(isalpha((unsigned char)type[*at]) || type[*at] == '_')) return 0;
            do { (*at)++; } while (*at < n && (isalnum((unsigned char)type[*at]) || type[*at] == '_'));
            if (*at >= n || type[*at] != '.') break;
            (*at)++;
        }
        if (*at + 1 < n && type[*at] == '[' && type[*at + 1] != ']') {
            (*at)++;
            if (!seed_array_type_parse(type, n, at, depth + 1)) return 0;
            while (*at < n && type[*at] == ',') {
                (*at)++;
                if (!seed_array_type_parse(type, n, at, depth + 1)) return 0;
            }
            if (*at >= n || type[*at] != ']') return 0;
            (*at)++;
        }
    }
    while (*at + 1 < n && type[*at] == '[' && type[*at + 1] == ']') *at += 2;
    return 1;
}

/* ARRAY_NEW carries a resolved canonical T[] and immediate length zero. */
static inline int seed_array_new_valid(const char *type, const char *length) {
    size_t n, at = 0;
    if (!type || !length || strcmp(length, "0") != 0) return 0;
    n = strlen(type);
    if (n < 3 || type[n - 2] != '[' || type[n - 1] != ']') return 0;
    return seed_array_type_parse(type, n, &at, 0) && at == n;
}
#endif
