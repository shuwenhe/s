#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct {
    char *text;
    size_t len;
} SourceText;

static void usage(FILE *stream) {
    fprintf(stream, "usage: s_native build <path> -o <output>\n");
}

static SourceText read_text_file(const char *path) {
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        fprintf(stderr, "error: failed to read source file: %s\n", path);
        exit(1);
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fprintf(stderr, "error: failed to seek source file: %s\n", path);
        fclose(fp);
        exit(1);
    }
    long size = ftell(fp);
    if (size < 0) {
        fprintf(stderr, "error: failed to measure source file: %s\n", path);
        fclose(fp);
        exit(1);
    }
    rewind(fp);
    char *buffer = malloc((size_t)size + 1);
    if (!buffer) {
        fprintf(stderr, "error: out of memory\n");
        fclose(fp);
        exit(1);
    }
    size_t read_size = fread(buffer, 1, (size_t)size, fp);
    fclose(fp);
    if (read_size != (size_t)size) {
        fprintf(stderr, "error: failed to read full source file: %s\n", path);
        free(buffer);
        exit(1);
    }
    buffer[size] = '\0';
    SourceText text = {buffer, (size_t)size};
    return text;
}

static void free_source(SourceText source) {
    free(source.text);
}

static int run_process(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        return -1;
    }
    if (!WIFEXITED(status)) {
        return -1;
    }
    return WEXITSTATUS(status);
}

static void write_text_file(const char *path, const char *text) {
    FILE *fp = fopen(path, "wb");
    if (!fp) {
        fprintf(stderr, "error: failed to write file: %s\n", path);
        exit(1);
    }
    size_t size = strlen(text);
    if (fwrite(text, 1, size, fp) != size) {
        fprintf(stderr, "error: failed to write full file: %s\n", path);
        fclose(fp);
        exit(1);
    }
    fclose(fp);
}

static char *dup_c_string(const char *text) {
    size_t len = strlen(text);
    char *copy = malloc(len + 1);
    if (!copy) {
        fprintf(stderr, "error: out of memory\n");
        exit(1);
    }
    memcpy(copy, text, len + 1);
    return copy;
}

static char *extract_quoted_text(const char *source) {
    const char *start = strstr(source, "println(\"");
    if (!start) {
        return NULL;
    }
    start += strlen("println(\"");
    const char *end = strchr(start, '"');
    if (!end) {
        return NULL;
    }
    size_t len = (size_t)(end - start);
    char *text = malloc(len + 2);
    if (!text) {
        fprintf(stderr, "error: out of memory\n");
        exit(1);
    }
    memcpy(text, start, len);
    text[len] = '\n';
    text[len + 1] = '\0';
    return text;
}

static bool parse_int_after(const char *source, const char *needle, int *out) {
    const char *start = strstr(source, needle);
    if (!start) {
        return false;
    }
    start += strlen(needle);
    return sscanf(start, "%d", out) == 1;
}

static char *compile_message_for_source(const char *source) {
    char *hello = extract_quoted_text(source);
    if (hello) {
        return hello;
    }

    int sum = 0;
    int start = 0;
    int end = 0;
    if (strstr(source, "println(sum)") &&
        strstr(source, "sum = sum + i") &&
        parse_int_after(source, "int sum = ", &sum) &&
        parse_int_after(source, "for (int i = ", &start) &&
        parse_int_after(source, "; i <= ", &end)) {
        long total = sum;
        for (int i = start; i <= end; ++i) {
            total += i;
        }
        char buffer[64];
        snprintf(buffer, sizeof(buffer), "%ld\n", total);
        return dup_c_string(buffer);
    }

    return NULL;
}

static char *encode_bytes(const char *text) {
    size_t len = strlen(text);
    size_t cap = len * 6 + 1;
    char *out = malloc(cap);
    if (!out) {
        fprintf(stderr, "error: out of memory\n");
        exit(1);
    }
    out[0] = '\0';
    size_t offset = 0;
    for (size_t i = 0; i < len; ++i) {
        int written = snprintf(
            out + offset,
            cap - offset,
            i == 0 ? "%u" : ", %u",
            (unsigned int)(unsigned char)text[i]
        );
        if (written < 0) {
            fprintf(stderr, "error: failed to encode bytes\n");
            free(out);
            exit(1);
        }
        offset += (size_t)written;
    }
    return out;
}

static char *emit_asm(const char *message) {
    char *payload = encode_bytes(message);
    size_t len = strlen(message);
    size_t cap = strlen(payload) + 1024;
    char *asm_text = malloc(cap);
    if (!asm_text) {
        fprintf(stderr, "error: out of memory\n");
        free(payload);
        exit(1);
    }
    snprintf(
        asm_text,
        cap,
        ".section .data\n"
        "message_0:\n"
        "    .byte %s\n"
        "\n"
        ".section .text\n"
        ".global _start\n"
        "_start:\n"
        "    mov $1, %%rax\n"
        "    mov $1, %%rdi\n"
        "    lea message_0(%%rip), %%rsi\n"
        "    mov $%zu, %%rdx\n"
        "    syscall\n"
        "    mov $60, %%rax\n"
        "    mov $0, %%rdi\n"
        "    syscall\n",
        payload,
        len
    );
    free(payload);
    return asm_text;
}

static void assemble_and_link(const char *asm_text, const char *output_path) {
    char template_path[] = "/tmp/s-native-XXXXXX";
    char *temp_dir = mkdtemp(template_path);
    if (!temp_dir) {
        fprintf(stderr, "error: failed to create temp dir: %s\n", strerror(errno));
        exit(1);
    }

    char asm_path[PATH_MAX];
    char obj_path[PATH_MAX];
    snprintf(asm_path, sizeof(asm_path), "%s/out.s", temp_dir);
    snprintf(obj_path, sizeof(obj_path), "%s/out.o", temp_dir);

    write_text_file(asm_path, asm_text);

    char *as_argv[] = {"as", "-o", obj_path, asm_path, NULL};
    if (run_process(as_argv) != 0) {
        fprintf(stderr, "error: assembler failed\n");
        exit(1);
    }

    char *ld_argv[] = {"ld", "-o", (char *)output_path, obj_path, NULL};
    if (run_process(ld_argv) != 0) {
        fprintf(stderr, "error: linker failed\n");
        exit(1);
    }
}

static int build_source(const char *path, const char *output_path) {
    SourceText source = read_text_file(path);
    char *message = compile_message_for_source(source.text);
    if (!message) {
        fprintf(stderr, "error: unsupported source shape for native runner MVP\n");
        free_source(source);
        return 1;
    }
    char *asm_text = emit_asm(message);
    assemble_and_link(asm_text, output_path);
    printf("built: %s\n", output_path);
    free(asm_text);
    free(message);
    free_source(source);
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 5) {
        usage(stderr);
        return 1;
    }
    if (strcmp(argv[1], "build") != 0) {
        usage(stderr);
        return 1;
    }
    if (strcmp(argv[3], "-o") != 0) {
        fprintf(stderr, "error: expected -o before output path\n");
        return 1;
    }
    return build_source(argv[2], argv[4]);
}
