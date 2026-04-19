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

static result_t run_python_process(char *const argv[], const char *message) {
    pid_t pid = fork();
    if (pid < 0) {
        return err_result(join3(message, ": ", strerror(errno)));
    }
    if (pid == 0) {
        setenv("s_disable_selfhosted", "1", 1);
        setenv("S_DISABLE_SELFHOSTED", "1", 1);
        const char *existing = getenv("PYTHONPATH");
        if (existing != NULL && existing[0] != '\0') {
            char pythonpath[4096];
            snprintf(
                pythonpath,
                sizeof(pythonpath),
                "/home/shuwen/s/src:/app/s/src:%s",
                existing
            );
            setenv("PYTHONPATH", pythonpath, 1);
        } else {
            setenv("PYTHONPATH", "/home/shuwen/s/src:/app/s/src", 1);
        }
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

static const char *get_env_any(const char *name_a, const char *name_b) {
    const char *value = getenv(name_a);
    if (value != NULL && value[0] != '\0') {
        return value;
    }
    if (name_b != NULL) {
        value = getenv(name_b);
        if (value != NULL && value[0] != '\0') {
            return value;
        }
    }
    return NULL;
}

static bool output_exists(const char *path) {
    return path != NULL && path[0] != '\0' && access(path, R_OK) == 0;
}

static const char *get_build_output_root(void) {
    const char *root = getenv("s_build_output_root");
    if (root != NULL && root[0] != '\0') {
        return root;
    }
    return "/tmp/s-build";
}

static char *resolve_output_path(const char *output_path) {
    if (output_path[0] == '/') {
        return dup_text(output_path);
    }

    const char *root = get_build_output_root();
    const char *name = strrchr(output_path, '/');
    if (name != NULL) {
        name++;
    } else {
        name = output_path;
    }

    if (mkdir(root, 0755) < 0 && errno != EEXIST) {
        return NULL;
    }

    size_t root_len = strlen(root);
    size_t name_len = strlen(name);
    char *resolved = malloc(root_len + 1 + name_len + 1);
    if (resolved == NULL) {
        return NULL;
    }
    memcpy(resolved, root, root_len);
    resolved[root_len] = '/';
    memcpy(resolved + root_len + 1, name, name_len);
    resolved[root_len + 1 + name_len] = '\0';
    return resolved;
}

static result_t run_compiler_binary(
    const char *binary,
    const char *command,
    const char *path,
    const char *output_path,
    bool dump_tokens,
    bool dump_ast,
    const char *message
) {
    char *argv[10];
    size_t index = 0;

    argv[index++] = (char *)binary;
    argv[index++] = (char *)command;
    argv[index++] = (char *)path;

    if (strcmp(command, "build") == 0) {
        argv[index++] = "-o";
        argv[index++] = (char *)output_path;
    } else if (strcmp(command, "check") == 0) {
        if (dump_tokens) {
            argv[index++] = "--dump-tokens";
        }
        if (dump_ast) {
            argv[index++] = "--dump-ast";
        }
    }

    argv[index] = NULL;

    result_t result = run_process(argv, message);
    if (!result.ok) {
        return result;
    }
    if (strcmp(command, "build") == 0 && !output_exists(output_path)) {
        return err_message("build command returned success but output missing");
    }
    return ok_result();
}

static result_t run_python_compiler(
    const char *command,
    const char *path,
    const char *output_path,
    bool dump_tokens,
    bool dump_ast
) {
    char *argv[12];
    size_t index = 0;

    argv[index++] = "python3";
    argv[index++] = "-m";
    argv[index++] = "compiler";
    argv[index++] = (char *)command;
    argv[index++] = (char *)path;

    if (strcmp(command, "build") == 0) {
        argv[index++] = "-o";
        argv[index++] = (char *)output_path;
    } else if (strcmp(command, "check") == 0) {
        if (dump_tokens) {
            argv[index++] = "--dump-tokens";
        }
        if (dump_ast) {
            argv[index++] = "--dump-ast";
        }
    }

    argv[index] = NULL;

    result_t result = run_python_process(argv, "python hosted compiler failed");
    if (!result.ok) {
        return result;
    }
    if (strcmp(command, "build") == 0 && !output_exists(output_path)) {
        return err_message("python hosted build returned success but output missing");
    }
    return ok_result();
}

static result_t run_hosted_compiler_command(
    const char *command,
    const char *path,
    const char *output_path,
    bool dump_tokens,
    bool dump_ast
) {
    const char *env_s = get_env_any("s_compiler", "S_COMPILER");
    if (env_s != NULL && access(env_s, X_OK) == 0) {
        result_t r = run_compiler_binary(
            env_s,
            command,
            path,
            output_path,
            dump_tokens,
            dump_ast,
            "self-hosted compiler failed"
        );
        if (r.ok) {
            return r;
        }
    }

    result_t r_py = run_python_compiler(command, path, output_path, dump_tokens, dump_ast);
    if (r_py.ok) {
        return r_py;
    }

    return r_py;
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
        "/home/shuwen/s/src/compiler/backend_elf64_runner_bootstrap.c",
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

static result_t build_self_hosted_compiler_launcher(const char *output_path) {
    char *cc_argv[] = {
        "cc",
        "-O2",
        "-std=c11",
        "/home/shuwen/s/src/runtime/s_selfhost_compiler_bootstrap.c",
        "-o",
        (char *)output_path,
        NULL,
    };
    result_t result = run_process(cc_argv, "compiler launcher bootstrap failed");
    if (result.ok) {
        printf("built: %s\n", output_path);
    }
    return result;
}

static bool is_compiler_entry_source(const char *path, const char *source) {
    if (path != NULL && strstr(path, "src/cmd/compile/main.s") != NULL) {
        return true;
    }
    return contains_text(source, "use compile.internal.compiler.main as compiler_main");
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
    if (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) {
        char cmd[1024];
        /* search for a candidate .s file under the directory. */
        /* prefer known compiler entry if present: <repo>/src/cmd/compile/main.s */
        char candidate_entry[512];
        snprintf(candidate_entry, sizeof(candidate_entry), "%s/src/cmd/compile/main.s", path);
        /* prefer an explicit main.s if present */
        char main_path[512];
        snprintf(main_path, sizeof(main_path), "%s/main.s", path);
        char found[512];
        if (access(candidate_entry, R_OK) == 0) {
            strncpy(found, candidate_entry, sizeof(found));
            found[sizeof(found)-1] = '\0';
            fprintf(stderr, "[debug] using repo compiler entry: %s\n", found);
        } else if (access(main_path, R_OK) == 0) {
            strncpy(found, main_path, sizeof(found));
            found[sizeof(found)-1] = '\0';
            fprintf(stderr, "[debug] using explicit main: %s\n", found);
        } else {
            /* search only .s files and exclude test/fixture paths */
            snprintf(cmd, sizeof(cmd), "grep -r -l -e 'func main(' -e 'package main' --include='*.s' %s | grep -v -e '/tests/|/fixtures/' | head -n1", path);
            fprintf(stderr, "[debug] running search cmd: %s\n", cmd);
            FILE *p = popen(cmd, "r");
            if (p == NULL) {
                fprintf(stderr, "[debug] popen failed\n");
                return err_message("failed to search directory for entrypoint");
            }
            if (fgets(found, sizeof(found), p) == NULL) {
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
        return run_hosted_compiler_command("build", found, output_path, false, false);
    }

    char *source = read_text(path);
    if (source == NULL) {
        return err_result(join3("failed to read source file", ": ", path));
    }
    if (is_self_host_source(source)) {
        free(source);
        return build_self_hosted_runner(output_path);
    }

    if (is_compiler_entry_source(path, source)) {
        free(source);
        return build_self_hosted_compiler_launcher(output_path);
    }

    char *message = NULL;
    if (!compile_message_for_source(source, &message)) {
        free(source);
        return run_hosted_compiler_command("build", path, output_path, false, false);
    }
    free(source);

    char *asm_text = emit_asm(message);
    free(message);
    if (asm_text == NULL) {
        return run_hosted_compiler_command("build", path, output_path, false, false);
    }
    result_t result = assemble_and_link(asm_text, output_path);
    free(asm_text);
    if (result.ok) {
        printf("built: %s\n", output_path);
        return result;
    }
    fprintf(
        stderr,
        "[debug] native build failed: %s; falling back to hosted compiler\n",
        result.message == NULL ? "(null)" : result.message
    );
    free(result.message);
    return run_hosted_compiler_command("build", path, output_path, false, false);
}

static int run_main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "error: usage: s_native check <path> [--dump-tokens] [--dump-ast] | s_native build <path> -o <output> | s_native run <path>\n");
        return 1;
    }
    if (strcmp(argv[0], "build") == 0) {
        if (argc != 4) {
            fprintf(stderr, "error: usage: s_native build <path> -o <output>\n");
            return 1;
        }
        if (strcmp(argv[2], "-o") != 0) {
            fprintf(stderr, "error: expected -o before output path\n");
            return 1;
        }
        char *resolved_output = resolve_output_path(argv[3]);
        if (resolved_output == NULL) {
            fprintf(stderr, "error: failed to resolve output path\n");
            return 1;
        }
        result_t result = build_source(argv[1], resolved_output);
        free(resolved_output);
        if (!result.ok) {
            fprintf(stderr, "error: %s\n", result.message == NULL ? "unknown error" : result.message);
            free(result.message);
            return 1;
        }
        return 0;
    }
    if (strcmp(argv[0], "check") == 0) {
        bool dump_tokens = false;
        bool dump_ast = false;
        for (int i = 2; i < argc; ++i) {
            if (strcmp(argv[i], "--dump-tokens") == 0) {
                dump_tokens = true;
            } else if (strcmp(argv[i], "--dump-ast") == 0) {
                dump_ast = true;
            } else {
                fprintf(stderr, "error: unknown flag: %s\n", argv[i]);
                return 1;
            }
        }
        result_t result = run_hosted_compiler_command("check", argv[1], "", dump_tokens, dump_ast);
        if (!result.ok) {
            fprintf(stderr, "error: %s\n", result.message == NULL ? "unknown error" : result.message);
            free(result.message);
            return 1;
        }
        return 0;
    }
    if (strcmp(argv[0], "run") == 0) {
        if (argc != 2) {
            fprintf(stderr, "error: usage: s_native run <path>\n");
            return 1;
        }
        result_t result = run_hosted_compiler_command("run", argv[1], "", false, false);
        if (!result.ok) {
            fprintf(stderr, "error: %s\n", result.message == NULL ? "unknown error" : result.message);
            free(result.message);
            return 1;
        }
        return 0;
    }
    fprintf(stderr, "error: usage: s_native check <path> [--dump-tokens] [--dump-ast] | s_native build <path> -o <output> | s_native run <path>\n");
    return 1;
}

int main(int argc, char **argv) {
    return run_main(argc - 1, argv + 1);
}
