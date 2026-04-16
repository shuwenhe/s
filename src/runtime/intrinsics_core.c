#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *dup_range(const char *start, size_t len) {
    char *out = (char *)malloc(len + 1);
    if (out == NULL) {
        return NULL;
    }
    memcpy(out, start, len);
    out[len] = '\0';
    return out;
}

static char *dup_cstr(const char *text) {
    if (text == NULL) {
        return NULL;
    }
    return dup_range(text, strlen(text));
}

void intrinsics_core_free(char *ptr) {
    free(ptr);
}

size_t intrinsics_core_string_len(const char *text) {
    if (text == NULL) {
        return 0;
    }
    return strlen(text);
}

char *intrinsics_core_int_to_string(long long value) {
    char buffer[64];
    int written = snprintf(buffer, sizeof(buffer), "%lld", value);
    if (written < 0) {
        return NULL;
    }
    size_t len = (size_t)written;
    if (len >= sizeof(buffer)) {
        char *out = (char *)malloc(len + 1);
        if (out == NULL) {
            return NULL;
        }
        snprintf(out, len + 1, "%lld", value);
        return out;
    }
    return dup_range(buffer, len);
}

char *intrinsics_core_string_concat(const char *left, const char *right) {
    if (left == NULL || right == NULL) {
        return NULL;
    }
    size_t left_len = strlen(left);
    size_t right_len = strlen(right);
    char *out = (char *)malloc(left_len + right_len + 1);
    if (out == NULL) {
        return NULL;
    }
    memcpy(out, left, left_len);
    memcpy(out + left_len, right, right_len);
    out[left_len + right_len] = '\0';
    return out;
}

char *intrinsics_core_string_replace(const char *text, const char *old_text, const char *new_text) {
    if (text == NULL || old_text == NULL || new_text == NULL) {
        return NULL;
    }
    size_t text_len = strlen(text);
    size_t old_len = strlen(old_text);
    size_t new_len = strlen(new_text);
    if (old_len == 0) {
        return dup_cstr(text);
    }

    size_t count = 0;
    const char *cursor = text;
    while ((cursor = strstr(cursor, old_text)) != NULL) {
        count++;
        cursor += old_len;
    }

    if (count == 0) {
        return dup_cstr(text);
    }

    size_t out_len = text_len + count * (new_len - old_len);
    char *out = (char *)malloc(out_len + 1);
    if (out == NULL) {
        return NULL;
    }

    const char *src = text;
    char *dst = out;
    while ((cursor = strstr(src, old_text)) != NULL) {
        size_t chunk = (size_t)(cursor - src);
        memcpy(dst, src, chunk);
        dst += chunk;
        memcpy(dst, new_text, new_len);
        dst += new_len;
        src = cursor + old_len;
    }
    size_t tail = strlen(src);
    memcpy(dst, src, tail);
    dst += tail;
    *dst = '\0';
    return out;
}

char *intrinsics_core_string_char_at(const char *text, long long index) {
    if (text == NULL || index < 0) {
        return NULL;
    }
    size_t len = strlen(text);
    if ((size_t)index >= len) {
        return NULL;
    }
    return dup_range(text + index, 1);
}

char *intrinsics_core_string_slice(const char *text, long long start, long long end) {
    if (text == NULL || start < 0 || end < start) {
        return NULL;
    }
    size_t len = strlen(text);
    if ((size_t)start > len) {
        return NULL;
    }
    size_t clipped_end = (size_t)end;
    if (clipped_end > len) {
        clipped_end = len;
    }
    return dup_range(text + start, clipped_end - (size_t)start);
}
