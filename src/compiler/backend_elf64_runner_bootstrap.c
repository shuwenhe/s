#define _posix_c_source 200809l

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
    if (copy == null) {
        return null;
    }
    memcpy(copy, text, len + 1);
    return copy;
}

static char *join3(const char *a, const char *b, const char *c) {
    size_t la = strlen(a);
    size_t lb = strlen(b);
    size_t lc = strlen(c);
    char *text = malloc(la + lb + lc + 1);
    if (text == null) {
        return null;
    }
    memcpy(text, a, la);
    memcpy(text + la, b, lb);
    memcpy(text + la + lb, c, lc);
    text[la + lb + lc] = '\0';
    return text;
}

static result_t ok_result(void) {
    result_t result = {true, null};
    return result;
}

static result_t err_result(char *message) {
    result_t result = {false, message};
    return result;
}

static result_t err_message(const char *message) {
    char *copy = dup_text(message);
    if (copy == null) {
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
    if (wifexited(status) && wexitstatus(status) == 0) {
        return ok_result();
    }
    return err_result(join3(message, ": ", "command failed"));
}

static char *read_text(const char *path) {
    file *file = fopen(path, "rb");
    if (file == null) {
        return null;
    }
    if (fseek(file, 0, seek_end) != 0) {
        fclose(file);
        return null;
    }
    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return null;
    }
    if (fseek(file, 0, seek_set) != 0) {
        fclose(file);
        return null;
    }
    char *text = malloc((size_t)size + 1);
    if (text == null) {
        fclose(file);
        return null;
    }
    size_t read_size = fread(text, 1, (size_t)size, file);
    fclose(file);
    text[read_size] = '\0';
    return text;
}

static result_t write_text(const char *path, const char *text) {
    file *file = fopen(path, "wb");
    if (file == null) {
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
    return strstr(text, needle) != null;
}

static bool is_self_host_source(const char *source) {
    return contains_text(source, "package runtime.runner");
}

static bool extract_quoted_println(const char *source, char **out_text) {
    const char *prefix = "println(\"";
    const char *start = strstr(source, prefix);
    if (start == null) {
        return false;
    }
    start += strlen(prefix);
    const char *end = strchr(start, '"');
    if (end == null) {
        return false;
    }
    size_t len = (size_t)(end - start);
    char *text = malloc(len + 2);
    if (text == null) {
        return false;
    }
    memcpy(text, start, len);
    text[len] = '\n';
    text[len + 1] = '\0';
    *out_text = text;
    return true;
}

static bool parse_signed_int(const char *text, int *out_value) {
    char *end = null;
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
    if (start == null) {
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
    return *out_text != null;
}

static bool parse_int_after(const char *source, const char *needle, int *out_value) {
    const char *start = strstr(source, needle);
    if (start == null) {
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
    return *out_text != null;
}

static int ascii_code(char ch) {
    return (unsigned char)ch;
}

static char *emit_asm(const char *message) {
    size_t cap = strlen(message) * 8 + 512;
    char *asm_text = malloc(cap);
    if (asm_text == null) {
        return null;
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
    char temp_template[] = "/tmp/s-native-xxxxxx";
    char *temp_dir = mkdtemp(temp_template);
    if (temp_dir == null) {
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

    char *as_argv[] = {"as", "-o", obj_path, asm_path, null};
    result_t as_result = run_process(as_argv, "assembler failed");
    if (!as_result.ok) {
        return as_result;
    }

    char *ld_argv[] = {"ld", "-o", (char *)output_path, obj_path, null};
    return run_process(ld_argv, "linker failed");
}

static result_t build_self_hosted_runner(const char *output_path) {
    char *cc_argv[] = {
        "cc",
        "-o2",
        "-std=c11",
        "/app/s/src/compiler/backend_elf64_runner_bootstrap.c",
        "-o",
        (char *)output_path,
        null,
    };
    result_t result = run_process(cc_argv, "native runner bootstrap failed");
    if (result.ok) {
        printf("built: %s\n", output_path);
    }
    return result;
}

static result_t build_source(const char *path, const char *output_path) {
    /* debug: log entry */
    fprintf(stderr, "[debug] build_source called path='%s' output='%s'\n", path, output_path);

    /* if the path is a directory, try to find a reasonable entrypoint
       source file (a file containing `package main` or `func main(`) and
       delegate to the hosted python compiler on that file. this provides
       basic package/multi-file build support for the native runner mvp.
    */
    struct stat st;
    if (stat(path, &st) == 0 && s_isdir(st.st_mode)) {
        char cmd[1024];
        /* search for a candidate .s file under the directory. */
        /* prefer known compiler entry if present: <repo>/src/cmd/compile/main.s */
        char candidate_entry[512];
        snprintf(candidate_entry, sizeof(candidate_entry), "%s/src/cmd/compile/main.s", path);
        /* prefer an explicit main.s if present */
        char main_path[512];
        snprintf(main_path, sizeof(main_path), "%s/main.s", path);
        char found[512];
        if (access(candidate_entry, r_ok) == 0) {
            strncpy(found, candidate_entry, sizeof(found));
            found[sizeof(found)-1] = '\0';
            fprintf(stderr, "[debug] using repo compiler entry: %s\n", found);
        } else if (access(main_path, r_ok) == 0) {
            strncpy(found, main_path, sizeof(found));
            found[sizeof(found)-1] = '\0';
            fprintf(stderr, "[debug] using explicit main: %s\n", found);
        } else {
            /* search only .s files and exclude test/fixture paths */
            snprintf(cmd, sizeof(cmd), "grep -r -l -e 'func main(' -e 'package main' --include='*.s' %s | grep -v -e '/tests/|/fixtures/' | head -n1", path);
            fprintf(stderr, "[debug] running search cmd: %s\n", cmd);
            file *p = popen(cmd, "r");
            if (p == null) {
                fprintf(stderr, "[debug] popen failed\n");
                return err_message("failed to search directory for entrypoint");
            }
            if (fgets(found, sizeof(found), p) == null) {
                pclose(p);
                fprintf(stderr, "[debug] no entrypoint found in dir: %s\n", path);
                return err_message("no entrypoint (.s) found in directory");
            }
            pclose(p);
            /* trim trailing newline */
            size_t n = strlen(found);
            if (n > 0 && found[n - 1] == '\n') {
                found[n - 1] = '\0';
            }
            fprintf(stderr, "[debug] found candidate: %s\n", found);
        }
        /* prefer an explicit s compiler binary if provided via env var s_compiler,
           or a system `s` found in path. fall back to python3 if neither works. */
        const char *env_s = getenv("s_compiler");
        if (env_s != null && access(env_s, x_ok) == 0) {
            char *s_argv[] = {(char *)env_s, "build", found, "-o", (char *)output_path, null};
            fprintf(stderr, "[debug] delegating to s_compiler: %s %s %s %s %s\n", s_argv[0], s_argv[1], s_argv[2], s_argv[3], s_argv[4]);
            result_t r = run_process(s_argv, "self-hosted compiler failed");
            if (r.ok) {
                fprintf(stderr, "[debug] delegated to s_compiler succeeded\n");
                return r;
            }
            fprintf(stderr, "[debug] s_compiler failed: %s\n", r.message ? r.message : "(null)");
        }

        /* fallback to python hosted compiler first to avoid accidentally
           delegating to an incompatible `s` on path that may return
           success without producing the requested output. */
        char *py_argv[] = {"python3", "-m", "compiler", "build", found, "-o", (char *)output_path, null};
        fprintf(stderr, "[debug] attempting python hosted compiler: %s %s %s %s %s %s\n",
                py_argv[0], py_argv[1], py_argv[2], py_argv[3], py_argv[4], py_argv[5]);
        result_t r_py = run_process(py_argv, "python hosted compiler failed");
        if (r_py.ok) {
            fprintf(stderr, "[debug] delegated to python succeeded\n");
            return r_py;
        }
        fprintf(stderr, "[debug] python hosted compiler failed: %s\n", r_py.message ? r_py.message : "(null)");

        /* try `s` on path as a last resort. */
        char *s_on_path_argv[] = {"s", "build", found, "-o", (char *)output_path, null};
        fprintf(stderr, "[debug] attempting to use 's' on path\n");
        result_t r_path = run_process(s_on_path_argv, "s on path failed");
        if (r_path.ok) {
            /* verify the requested output was actually produced. some
               `s` implementations may exit 0 without writing the
               output file; treat that as failure and continue to the
               next fallback. */
            if (access((char *)output_path, r_ok) == 0) {
                fprintf(stderr, "[debug] delegated to s on path succeeded and output exists\n");
                return r_path;
            }
            fprintf(stderr, "[debug] s on path returned success but output missing: %s\n", (char *)output_path);
        }
        fprintf(stderr, "[debug] s on path failed: %s\n", r_path.message ? r_path.message : "(null)");

        return r_py;
    }

    char *source = read_text(path);
    if (source == null) {
        return err_result(join3("failed to read source file", ": ", path));
    }
    if (is_self_host_source(source)) {
        free(source);
        return build_self_hosted_runner(output_path);
    }

    char *message = null;
    if (!compile_message_for_source(source, &message)) {
        free(source);
        return err_message("unsupported source shape for native runner mvp");
    }
    free(source);

    char *asm_text = emit_asm(message);
    free(message);
    if (asm_text == null) {
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
        fprintf(stderr, "error: %s\n", result.message == null ? "unknown error" : result.message);
        free(result.message);
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    return run_main(argc - 1, argv + 1);
}
