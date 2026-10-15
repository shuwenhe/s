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

/* ARRAY_NEW carries a resolved canonical T[] and the immediate length zero. */
static inline int seed_array_new_valid(const char *type, const char *length) {
    size_t n, i;
    if (!type || !length || strcmp(length, "0") != 0) return 0;
    n = strlen(type);
    if (n < 3 || type[n - 2] != '[' || type[n - 1] != ']') return 0;
    while (n >= 2 && type[n - 2] == '[' && type[n - 1] == ']') n -= 2;
    if (n == 0 || !(isalpha((unsigned char)type[0]) || type[0] == '_')) return 0;
    for (i = 1; i < n; i++) {
        if (!(isalnum((unsigned char)type[i]) || type[i] == '_' || type[i] == '.')) return 0;
    }
    return 1;
}
#endif
