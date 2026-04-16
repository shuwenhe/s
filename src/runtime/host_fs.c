#define _POSIX_C_SOURCE 200809L

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

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

void host_fs_free(char *ptr) {
    free(ptr);
}

static void mkdirs_for_path(const char *path) {
    if (path == NULL || *path == '\0') {
        return;
    }
    char *scratch = dup_cstr(path);
    if (scratch == NULL) {
        return;
    }
    for (char *p = scratch + 1; *p != '\0'; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(scratch, 0755);
            *p = '/';
        }
    }
    free(scratch);
}

char *host_fs_read_to_string(const char *path) {
    if (path == NULL) {
        return NULL;
    }
    FILE *fp = fopen(path, "rb");
    if (fp == NULL) {
        return NULL;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return NULL;
    }
    long size = ftell(fp);
    if (size < 0) {
        fclose(fp);
        return NULL;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return NULL;
    }
    char *buffer = (char *)malloc((size_t)size + 1);
    if (buffer == NULL) {
        fclose(fp);
        return NULL;
    }
    size_t read = fread(buffer, 1, (size_t)size, fp);
    fclose(fp);
    buffer[read] = '\0';
    return buffer;
}

int host_fs_write_text_file(const char *path, const char *contents) {
    if (path == NULL || contents == NULL) {
        return -1;
    }
    mkdirs_for_path(path);
    FILE *fp = fopen(path, "wb");
    if (fp == NULL) {
        return -1;
    }
    size_t len = strlen(contents);
    size_t written = fwrite(contents, 1, len, fp);
    fclose(fp);
    return written == len ? 0 : -1;
}

char *host_fs_make_temp_dir(const char *prefix, const char *base_dir) {
    const char *prefix_text = prefix == NULL ? "tmp-" : prefix;
    const char *root = base_dir == NULL ? "/tmp" : base_dir;
    mkdirs_for_path(root);
    char template_path[512];
    snprintf(template_path, sizeof(template_path), "%s/%sXXXXXX", root, prefix_text);
    char *result = dup_cstr(template_path);
    if (result == NULL) {
        return NULL;
    }
    if (mkdtemp(result) == NULL) {
        free(result);
        return NULL;
    }
    return result;
}
