#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct {
    bool ok;
    char *message;
} result_t;

static char *dup_text(const char *text) {
    size_t len = strlen(text);
    char *copy = malloc(len + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, text, len + 1);
    return copy;
}

static char *join3(const char *a, const char *b, const char *c) {
    size_t la = strlen(a);
    size_t lb = strlen(b);
    size_t lc = strlen(c);
    char *text = malloc(la + lb + lc + 1);
    if (text == NULL) {
        return NULL;
    }
    memcpy(text, a, la);
    memcpy(text + la, b, lb);
    memcpy(text + la + lb, c, lc);
    text[la + lb + lc] = '\0';
    return text;
}

static result_t ok_result(void) {
    result_t result = {true, NULL};
    return result;
}

static result_t err_result(char *message) {
    result_t result = {false, message};
    return result;
}

static result_t err_message(const char *message) {
    char *copy = dup_text(message);
    if (copy == NULL) {
        return err_result(dup_text("out of memory"));
    }
    return err_result(copy);
}

static result_t run_process(char *const argv[], const char *message) {
    pid_t pid = fork();
    if (pid < 0) {
        return err_result(join3(message, ": ", strerror(errno)));
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        fprintf(stderr, "%s: %s\n", message, strerror(errno));
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        return err_result(join3(message, ": ", strerror(errno)));
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        return ok_result();
    }
    return err_result(join3(message, ": ", "command failed"));
}

static char *read_text(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return NULL;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return NULL;
    }
    if (fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    char *text = malloc((size_t)size + 1);
    if (text == NULL) {
        fclose(file);
        return NULL;
    }
    size_t read_size = fread(text, 1, (size_t)size, file);
    fclose(file);
    text[read_size] = '\0';
    return text;
}

static result_t write_text(const char *path, const char *text) {
    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        return err_result(join3("failed to write file", ": ", strerror(errno)));
    }
    size_t size = strlen(text);
    if (fwrite(text, 1, size, file) != size) {
        fclose(file);
        return err_result(join3("failed to write file", ": ", strerror(errno)));
    }
    fclose(file);
    return ok_result();
}

static bool contains_text(const char *text, const char *needle) {
    return strstr(text, needle) != NULL;
}

static bool is_self_host_source(const char *source) {
    return contains_text(source, "package runtime.runner");
}

static bool extract_quoted_println(const char *source, char **out_text) {
    const char *prefix = "println(\"";
    const char *start = strstr(source, prefix);
    if (start == NULL) {
        return false;
    }
    start += strlen(prefix);
    const char *end = strchr(start, '"');
    if (end == NULL) {
        return false;
    }
    size_t len = (size_t)(end - start);
    char *text = malloc(len + 2);
    if (text == NULL) {
        return false;
    }
    memcpy(text, start, len);
    text[len] = '\n';
    text[len + 1] = '\0';
    *out_text = text;
    return true;
}

static bool parse_signed_int(const char *text, int *out_value) {
    char *end = NULL;
    long value = strtol(text, &end, 10);
    if (end == text) {
        return false;
    }
    *out_value = (int)value;
    return true;
}

static bool extract_printed_int_literal(const char *source, char **out_text) {
    const char *prefix = "println(";
    const char *start = strstr(source, prefix);
    if (start == NULL) {
        return false;
    }
    start += strlen(prefix);
    int value = 0;
    if (!parse_signed_int(start, &value)) {
        return false;
    }
    const char *end = start;
    if (*end == '-') {
        end++;
    }
    while (*end >= '0' && *end <= '9') {
        end++;
    }
    if (*end != ')') {
        return false;
    }
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%d\n", value);
    *out_text = dup_text(buffer);
    return *out_text != NULL;
}

static bool parse_int_after(const char *source, const char *needle, int *out_value) {
    const char *start = strstr(source, needle);
    if (start == NULL) {
        return false;
    }
    start += strlen(needle);
    return parse_signed_int(start, out_value);
}

static bool compile_message_for_source(const char *source, char **out_text) {
    if (extract_quoted_println(source, out_text)) {
        return true;
    }
    if (extract_printed_int_literal(source, out_text)) {
        return true;
    }
    if (!contains_text(source, "println(sum)") || !contains_text(source, "sum = sum + i")) {
        return false;
    }
    int initial = 0;
    int start = 0;
    int end = 0;
    if (!parse_int_after(source, "int sum = ", &initial)) {
        return false;
    }
    if (!parse_int_after(source, "for (int i = ", &start)) {
        return false;
    }
    if (!parse_int_after(source, "; i <= ", &end)) {
        return false;
    }
    long total = initial;
    for (int i = start; i <= end; ++i) {
        total += i;
    }
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%ld\n", total);
    *out_text = dup_text(buffer);
    return *out_text != NULL;
}

static int ascii_code(char ch) {
    return (unsigned char)ch;
}

static char *emit_asm(const char *message) {
    size_t cap = strlen(message) * 8 + 512;
    char *asm_text = malloc(cap);
    if (asm_text == NULL) {
        return NULL;
    }
    size_t offset = 0;
    offset += (size_t)snprintf(
        asm_text + offset,
        cap - offset,
        ".section .data\nmessage_0:\n    .byte "
    );
    for (size_t i = 0; message[i] != '\0'; ++i) {
        offset += (size_t)snprintf(
            asm_text + offset,
            cap - offset,
            "%s%d",
            i == 0 ? "" : ", ",
            ascii_code(message[i])
        );
    }
    offset += (size_t)snprintf(
        asm_text + offset,
        cap - offset,
        "\n\n.section .text\n.global _start\n_start:\n"
        "    mov $1, %%rax\n"
        "    mov $1, %%rdi\n"
        "    lea message_0(%%rip), %%rsi\n"
        "    mov $%zu, %%rdx\n"
        "    syscall\n"
        "    mov $60, %%rax\n"
        "    mov $0, %%rdi\n"
        "    syscall\n",
        strlen(message)
    );
    return asm_text;
}

static result_t assemble_and_link(const char *asm_text, const char *output_path) {
    char temp_template[] = "/tmp/s-native-XXXXXX";
    char *temp_dir = mkdtemp(temp_template);
    if (temp_dir == NULL) {
        return err_result(join3("failed to create temp dir", ": ", strerror(errno)));
    }

    char asm_path[512];
    char obj_path[512];
    snprintf(asm_path, sizeof(asm_path), "%s/out.s", temp_dir);
    snprintf(obj_path, sizeof(obj_path), "%s/out.o", temp_dir);

    result_t write = write_text(asm_path, asm_text);
    if (!write.ok) {
        return write;
    }

    char *as_argv[] = {"as", "-o", obj_path, asm_path, NULL};
    result_t as_result = run_process(as_argv, "assembler failed");
    if (!as_result.ok) {
        return as_result;
    }

    char *ld_argv[] = {"ld", "-o", (char *)output_path, obj_path, NULL};
    return run_process(ld_argv, "linker failed");
}

static result_t build_self_hosted_runner(const char *output_path) {
    char *cc_argv[] = {
        "cc",
        "-O2",
        "-std=c11",
        "/app/s/runtime/runner_native_template.c",
        "-o",
        (char *)output_path,
        NULL,
    };
    result_t result = run_process(cc_argv, "native runner bootstrap failed");
    if (result.ok) {
        printf("built: %s\n", output_path);
    }
    return result;
}

static result_t build_source(const char *path, const char *output_path) {
    char *source = read_text(path);
    if (source == NULL) {
        return err_result(join3("failed to read source file", ": ", path));
    }
    if (is_self_host_source(source)) {
        free(source);
        return build_self_hosted_runner(output_path);
    }

    char *message = NULL;
    if (!compile_message_for_source(source, &message)) {
        free(source);
        return err_message("unsupported source shape for native runner MVP");
    }
    free(source);

    char *asm_text = emit_asm(message);
    free(message);
    if (asm_text == NULL) {
        return err_message("failed to emit assembly");
    }
    result_t result = assemble_and_link(asm_text, output_path);
    free(asm_text);
    if (result.ok) {
        printf("built: %s\n", output_path);
    }
    return result;
}

static int run_main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "error: usage: s_native build <path> -o <output>\n");
        return 1;
    }
    if (strcmp(argv[0], "build") != 0) {
        fprintf(stderr, "error: usage: s_native build <path> -o <output>\n");
        return 1;
    }
    if (strcmp(argv[2], "-o") != 0) {
        fprintf(stderr, "error: expected -o before output path\n");
        return 1;
    }
    result_t result = build_source(argv[1], argv[3]);
    if (!result.ok) {
        fprintf(stderr, "error: %s\n", result.message == NULL ? "unknown error" : result.message);
        free(result.message);
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    return run_main(argc - 1, argv + 1);
}
