#define _POSIX_C_SOURCE 200809L

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char **g_args = NULL;
static size_t g_argc = 0;

static void free_args(void) {
    if (g_args == NULL) {
        return;
    }
    for (size_t i = 0; i < g_argc; i++) {
        free(g_args[i]);
    }
    free(g_args);
    g_args = NULL;
    g_argc = 0;
}

static char *dup_cstr(const char *text) {
    if (text == NULL) {
        return NULL;
    }
    size_t len = strlen(text);
    char *out = (char *)malloc(len + 1);
    if (out == NULL) {
        return NULL;
    }
    memcpy(out, text, len);
    out[len] = '\0';
    return out;
}

int host_intrinsics_init(size_t argc, const char *const *argv) {
    free_args();
    if (argc == 0 || argv == NULL) {
        return 0;
    }
    if (argc <= 1) {
        return 0;
    }
    g_argc = argc - 1;
    g_args = (char **)calloc(g_argc, sizeof(char *));
    if (g_args == NULL) {
        g_argc = 0;
        return -1;
    }
    for (size_t i = 0; i < g_argc; i++) {
        g_args[i] = dup_cstr(argv[i + 1]);
        if (g_args[i] == NULL) {
            free_args();
            return -1;
        }
    }
    return 0;
}

size_t host_intrinsics_argc(void) {
    return g_argc;
}

const char *host_intrinsics_argv(size_t index) {
    if (index >= g_argc || g_args == NULL) {
        return NULL;
    }
    return g_args[index];
}

const char *host_intrinsics_get_env(const char *key) {
    if (key == NULL) {
        return NULL;
    }
    return getenv(key);
}

void host_intrinsics_println(const char *text) {
    fputs(text == NULL ? "" : text, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

void host_intrinsics_eprintln(const char *text) {
    fputs(text == NULL ? "" : text, stderr);
    fputc('\n', stderr);
    fflush(stderr);
}
