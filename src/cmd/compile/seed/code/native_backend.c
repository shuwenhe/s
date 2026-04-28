#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "target.h"

static bool read_text_file(const char *path, char **out_text, compile_error *err) {
	FILE *fp;
	long n;
	size_t read_n;
	char *buf;

	*out_text = NULL;
	fp = fopen(path, "rb");
	if (!fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open IR input: %s", path);
		return false;
	}
	if (fseek(fp, 0, SEEK_END) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to seek IR input: %s", path);
		return false;
	}
	n = ftell(fp);
	if (n < 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to measure IR input: %s", path);
		return false;
	}
	if (fseek(fp, 0, SEEK_SET) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to rewind IR input: %s", path);
		return false;
	}

	buf = (char *)malloc((size_t)n + 1);
	if (!buf) {
		fclose(fp);
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}

	read_n = fread(buf, 1, (size_t)n, fp);
	fclose(fp);
	if (read_n != (size_t)n) {
		free(buf);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to read IR input: %s", path);
		return false;
	}
	buf[n] = '\0';
	*out_text = buf;
	return true;
}

static bool write_escaped_ir(FILE *out, const char *ir_text, compile_error *err) {
	const char *p = ir_text;

	if (fprintf(out, "static const char *embedded_ir =\n") < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
		return false;
	}

	while (*p) {
		if (fputc('"', out) == EOF) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
			return false;
		}
		while (*p && *p != '\n') {
			char ch = *p++;
			if (ch == '\\' || ch == '"') {
				if (fputc('\\', out) == EOF || fputc(ch, out) == EOF) {
					error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
					return false;
				}
			} else if (ch == '\r') {
				if (fprintf(out, "\\r") < 0) {
					error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
					return false;
				}
			} else if (ch == '\t') {
				if (fprintf(out, "\\t") < 0) {
					error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
					return false;
				}
			} else {
				if (fputc(ch, out) == EOF) {
					error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
					return false;
				}
			}
		}
		if (*p == '\n') {
			p++;
			if (fprintf(out, "\\n\"\n") < 0) {
				error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
				return false;
			}
		} else {
			if (fprintf(out, "\"\n") < 0) {
				error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
				return false;
			}
		}
	}

	if (fprintf(out, ";\n") < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
		return false;
	}

	return true;
}

static bool write_runner_c_file(FILE *out, const char *ir_text, compile_error *err) {
	if (fprintf(out,
		"#include <stdio.h>\n"
		"#include <stdlib.h>\n"
		"#include <string.h>\n"
		"#include \"runtime/memory.h\"\n"
		"#include \"error/error.h\"\n\n"
		"bool emit_native_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err);\n\n"
		"static const char *embedded_ir;\n\n"
		"static void print_compile_error(const compile_error *err) {\n"
		"    if (!err || !error_is_set(err)) {\n"
		"        return;\n"
		"    }\n"
		"    fprintf(stderr, \"error[%%d] at %%zu:%%zu: %%s\\n\", (int)err->code, err->line, err->column, err->message);\n"
		"}\n\n"
		"static void print_usage(const char *argv0) {\n"
		"    fprintf(stderr, \"usage:\\n\");\n"
		"    fprintf(stderr, \"  %%s <input.s> <output.ir>\\n\", argv0);\n"
		"    fprintf(stderr, \"  %%s --emit-bin <input.ir> <output.bin>\\n\", argv0);\n"
		"    fprintf(stderr, \"  %%s --bootstrap <compiler_source.s> [output_dir]\\n\", argv0);\n"
		"}\n\n"
		"static int run_embedded_compile(const char *input_path, const char *output_path) {\n"
		"    long ret = 0;\n"
		"    compile_error err;\n"
		"    char *argv_local[3];\n"
		"    error_clear(&err);\n"
		"    argv_local[0] = \"embedded-compiler\";\n"
		"    argv_local[1] = (char *)input_path;\n"
		"    argv_local[2] = (char *)output_path;\n"
		"    if (!runtime_execute_text_with_argv(embedded_ir, \"main\", &ret, &err, 3, argv_local)) {\n"
		"        print_compile_error(&err);\n"
		"        return 1;\n"
		"    }\n"
		"    return (int)ret;\n"
		"}\n\n"
		"static int files_equal(const char *path1, const char *path2) {\n"
		"    FILE *a = fopen(path1, \"rb\");\n"
		"    FILE *b = fopen(path2, \"rb\");\n"
		"    int ok = 1;\n"
		"    if (!a || !b) {\n"
		"        if (a) fclose(a);\n"
		"        if (b) fclose(b);\n"
		"        return 0;\n"
		"    }\n"
		"    for (;;) {\n"
		"        int ca = fgetc(a);\n"
		"        int cb = fgetc(b);\n"
		"        if (ca != cb) { ok = 0; break; }\n"
		"        if (ca == EOF) { break; }\n"
		"    }\n"
		"    fclose(a);\n"
		"    fclose(b);\n"
		"    return ok;\n"
		"}\n\n"
		"static int run_embedded_bootstrap(const char *compiler_src, const char *out_dir) {\n"
		"    char stage1[512];\n"
		"    char stage2[512];\n"
		"    snprintf(stage1, sizeof(stage1), \"%%s/stage1.ir\", out_dir);\n"
		"    snprintf(stage2, sizeof(stage2), \"%%s/stage2.ir\", out_dir);\n"
		"    {\n"
		"        char mkdir_cmd[768];\n"
		"        snprintf(mkdir_cmd, sizeof(mkdir_cmd), \"mkdir -p '%%s'\", out_dir);\n"
		"        if (system(mkdir_cmd) != 0) {\n"
		"            fprintf(stderr, \"error[5] at 0:0: failed to create dir: %%s\\n\", out_dir);\n"
		"            return 1;\n"
		"        }\n"
		"    }\n"
		"    if (run_embedded_compile(compiler_src, stage1) != 0) {\n"
		"        return 1;\n"
		"    }\n"
		"    if (run_embedded_compile(compiler_src, stage2) != 0) {\n"
		"        return 1;\n"
		"    }\n"
		"    if (!files_equal(stage1, stage2)) {\n"
		"        fprintf(stderr, \"error[5] at 0:0: bootstrap mismatch: stage1 and stage2 outputs differ\\n\");\n"
		"        return 1;\n"
		"    }\n"
		"    printf(\"bootstrap two-stage check passed\\n\");\n"
		"    return 0;\n"
		"}\n\n") < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
		return false;
	}

	if (!write_escaped_ir(out, ir_text, err)) {
		return false;
	}

	if (fprintf(out,
		"\nint main(int argc, char **argv) {\n"
		"    compile_error err;\n"
		"    if (argc >= 2 && strcmp(argv[1], \"--emit-bin\") == 0) {\n"
		"        error_clear(&err);\n"
		"        if (argc != 4) {\n"
		"            print_usage(argv[0]);\n"
		"            return 2;\n"
		"        }\n"
		"        if (!emit_native_from_ir_file(argv[2], argv[3], &err)) {\n"
		"            print_compile_error(&err);\n"
		"            return 1;\n"
		"        }\n"
		"        printf(\"compiled %%s -> %%s\\n\", argv[2], argv[3]);\n"
		"        return 0;\n"
		"    }\n"
		"    if (argc >= 2 && strcmp(argv[1], \"--bootstrap\") == 0) {\n"
		"        const char *out_dir = \".\";\n"
		"        if (argc < 3 || argc > 4) {\n"
		"            print_usage(argv[0]);\n"
		"            return 2;\n"
		"        }\n"
		"        if (argc == 4) {\n"
		"            out_dir = argv[3];\n"
		"        }\n"
		"        return run_embedded_bootstrap(argv[2], out_dir);\n"
		"    }\n"
		"    if (argc != 3) {\n"
		"        print_usage(argv[0]);\n"
		"        return 2;\n"
		"    }\n"
		"    return run_embedded_compile(argv[1], argv[2]);\n"
		"}\n") < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
		return false;
	}

	return true;
}

bool emit_native_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err) {
	char *ir_text = NULL;
	char temp_path[256];
	char command[2048];
	FILE *out;
	int rc;

	error_clear(err);
	if (!input_ir_path || !output_binary_path) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid native backend input");
		return false;
	}

	if (!read_text_file(input_ir_path, &ir_text, err)) {
		return false;
	}
	if (strncmp(ir_text, "SSEED-TARGET-V1", strlen("SSEED-TARGET-V1")) != 0) {
		free(ir_text);
		error_set(err, ERR_SEMANTIC, 1, 1, "invalid IR header");
		return false;
	}

	snprintf(temp_path, sizeof(temp_path), "/tmp/s_seed_native_%ld_%ld.c", (long)getpid(), (long)time(NULL));
	out = fopen(temp_path, "wb");
	if (!out) {
		free(ir_text);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open temporary source file");
		return false;
	}

	if (!write_runner_c_file(out, ir_text, err)) {
		free(ir_text);
		fclose(out);
		remove(temp_path);
		return false;
	}
	free(ir_text);

	if (fclose(out) != 0) {
		remove(temp_path);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close temporary source file");
		return false;
	}

	snprintf(command, sizeof(command),
		"gcc -std=c11 -O2 -Wall -Wextra -Werror -I src/cmd/compile/seed -o %s %s "
		"src/cmd/compile/seed/runtime/runtime.c src/cmd/compile/seed/error/error.c "
		"src/cmd/compile/seed/code/native_backend.c "
		"src/cmd/compile/seed/lexical/lexer.c src/cmd/compile/seed/syntax/parser.c "
		"src/cmd/compile/seed/semantic/analyzer.c src/cmd/compile/seed/intermediate/ir.c "
		"src/cmd/compile/seed/code/generator.c",
		output_binary_path,
		temp_path);

	rc = system(command);
	remove(temp_path);
	if (rc != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "native code generation command failed");
		return false;
	}

	return true;
}