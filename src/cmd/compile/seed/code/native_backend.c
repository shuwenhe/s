#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <ctype.h>

#include "target.h"

typedef struct c_abi_export {
	char function[256];
	char symbol[256];
	size_t argc;
} c_abi_export;

static int native_is_c_identifier(const char *s) {
	const unsigned char *p = (const unsigned char *)s;
	if (!p || !(isalpha(*p) || *p == '_')) return 0;
	for (p++; *p; p++) if (!(isalnum(*p) || *p == '_')) return 0;
	return 1;
}

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
		"static int run_embedded_program(int argc, char **argv) {\n"
		"    long ret = 0;\n"
		"    compile_error err;\n"
		"    error_clear(&err);\n"
		"    if (!runtime_execute_text_with_argv(embedded_ir, \"main\", &ret, &err, argc, argv)) {\n"
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
		"    return run_embedded_program(argc, argv);\n"
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

	const char *s_source_root = getenv("S_SOURCE_ROOT");
	if (!s_source_root) {
		s_source_root = ".";
	}

	snprintf(command, sizeof(command),
		"gcc -std=c11 -O2 -Wall -Wextra -Werror -DSEED_COMPILE_ONLY -I %s/src/cmd/compile/seed -o %s %s "
		"%s/src/cmd/compile/seed/runtime/runtime.c %s/src/cmd/compile/seed/error/error.c "
		"%s/src/cmd/compile/seed/code/native_backend.c "
		"%s/src/cmd/compile/seed/lexical/lexer.c %s/src/cmd/compile/seed/syntax/parser.c "
		"%s/src/cmd/compile/seed/semantic/analyzer.c %s/src/cmd/compile/seed/intermediate/ir.c "
		"%s/src/cmd/compile/seed/code/generator.c %s/src/cmd/compile/seed/bootstrap/bootstrap.c "
		"%s/src/cmd/compile/seed/s_seed.c",
		s_source_root,
		output_binary_path,
		temp_path,
		s_source_root, s_source_root,
		s_source_root,
		s_source_root, s_source_root,
		s_source_root, s_source_root,
		s_source_root, s_source_root, s_source_root);

	rc = system(command);
	remove(temp_path);
	if (rc != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "native code generation command failed");
		return false;
	}

	return true;
}

static bool collect_c_abi_exports(const char *ir_text, c_abi_export *exports, size_t cap, size_t *out_len, compile_error *err) {
	const char *line = ir_text;
	size_t len = 0;
	while (line && *line) {
		const char *end = strchr(line, '\n');
		size_t line_len = end ? (size_t)(end - line) : strlen(line);
		if (line_len > 7 && strncmp(line, "EXPORT|", 7) == 0) {
			char record[1536];
			char *function;
			char *symbol;
			char *signature;
			char *cursor;
			size_t argc = 0;
			if (line_len >= sizeof(record) || len >= cap) {
				error_set(err, ERR_SEMANTIC, 0, 0, "too many or oversized C ABI exports");
				return false;
			}
			memcpy(record, line + 7, line_len - 7);
			record[line_len - 7] = '\0';
			function = record;
			symbol = strchr(function, '|');
			if (!symbol) goto invalid_record;
			*symbol++ = '\0';
			signature = strchr(symbol, '|');
			if (!signature) goto invalid_record;
			*signature++ = '\0';
			if (strcmp(signature, "int") != 0 && strncmp(signature, "int,", 4) != 0) goto invalid_signature;
			if (!native_is_c_identifier(function) || !native_is_c_identifier(symbol) || strcmp(symbol, "s_abi_last_error") == 0) {
				error_set(err, ERR_SEMANTIC, 0, 0, "invalid or reserved C ABI export name");
				return false;
			}
			cursor = signature + 3;
			while (*cursor) {
				if (*cursor != ',' || strncmp(cursor + 1, "int", 3) != 0) goto invalid_signature;
				argc++;
				cursor += 4;
			}
			if (strlen(function) >= sizeof(exports[len].function) || strlen(symbol) >= sizeof(exports[len].symbol)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "C ABI export name is too long");
				return false;
			}
			{
				size_t previous;
				for (previous = 0; previous < len; previous++) {
					if (strcmp(exports[previous].symbol, symbol) == 0) {
						error_set(err, ERR_SEMANTIC, 0, 0, "duplicate C ABI export symbol: %s", symbol);
						return false;
					}
				}
			}
			strcpy(exports[len].function, function);
			strcpy(exports[len].symbol, symbol);
			exports[len].argc = argc;
			len++;
		}
		line = end ? end + 1 : NULL;
	}
	if (len == 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "IR contains no C ABI exports");
		return false;
	}
	*out_len = len;
	return true;

invalid_record:
	error_set(err, ERR_SEMANTIC, 0, 0, "invalid C ABI EXPORT record");
	return false;
invalid_signature:
	error_set(err, ERR_SEMANTIC, 0, 0, "unsupported C ABI signature; only S int is currently supported");
	return false;
}

static bool write_c_abi_library_file(FILE *out, const char *ir_text, const c_abi_export *exports, size_t export_count, compile_error *err) {
	size_t i;
	if (fprintf(out,
		"#include <stdint.h>\n"
		"#include <stdio.h>\n"
		"#include <string.h>\n"
		"#include \"runtime/memory.h\"\n"
		"#include \"error/error.h\"\n\n"
		"static _Thread_local char s_c_abi_error[512];\n"
		"__attribute__((visibility(\"default\"))) const char *s_abi_last_error(void) { return s_c_abi_error; }\n\n") < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to write C ABI source");
		return false;
	}
	if (!write_escaped_ir(out, ir_text, err)) return false;
	for (i = 0; i < export_count; i++) {
		size_t arg;
		if (fprintf(out, "\n__attribute__((visibility(\"default\"))) int64_t %s(", exports[i].symbol) < 0) return false;
		for (arg = 0; arg < exports[i].argc; arg++) {
			if (fprintf(out, "%sint64_t a%zu", arg ? ", " : "", arg) < 0) return false;
		}
		if (fprintf(out, ") {\n    compile_error err;\n    int64_t ret = 0;\n") < 0) return false;
		if (exports[i].argc > 0) {
			if (fprintf(out, "    int64_t args[%zu] = {", exports[i].argc) < 0) return false;
			for (arg = 0; arg < exports[i].argc; arg++) {
				if (fprintf(out, "%sa%zu", arg ? ", " : "", arg) < 0) return false;
			}
			if (fprintf(out, "};\n") < 0) return false;
		}
		if (fprintf(out,
			"    error_clear(&err);\n"
			"    s_c_abi_error[0] = '\\0';\n"
			"    if (!runtime_execute_text_i64(embedded_ir, \"%s\", %s, %zu, &ret, &err)) {\n"
			"        snprintf(s_c_abi_error, sizeof(s_c_abi_error), \"%%s\", err.message);\n"
			"        return 0;\n"
			"    }\n"
			"    return (int64_t)ret;\n"
			"}\n",
			exports[i].function, exports[i].argc ? "args" : "NULL", exports[i].argc) < 0) return false;
	}
	return true;
}

bool emit_c_abi_shared_from_ir_file(const char *input_ir_path, const char *output_library_path, compile_error *err) {
	char *ir_text = NULL;
	c_abi_export exports[64];
	size_t export_count = 0;
	char temp_path[256];
	char command[2048];
	const char *s_source_root;
	const char *shared_flag;
	FILE *out;
	int rc;

	error_clear(err);
	if (!input_ir_path || !output_library_path || !read_text_file(input_ir_path, &ir_text, err)) return false;
	if (strncmp(ir_text, "SSEED-TARGET-V1", strlen("SSEED-TARGET-V1")) != 0) {
		free(ir_text);
		error_set(err, ERR_SEMANTIC, 1, 1, "invalid IR header");
		return false;
	}
	if (!collect_c_abi_exports(ir_text, exports, 64, &export_count, err)) {
		free(ir_text);
		return false;
	}
	snprintf(temp_path, sizeof(temp_path), "/tmp/s_seed_cabi_%ld_%ld.c", (long)getpid(), (long)time(NULL));
	out = fopen(temp_path, "wb");
	if (!out) {
		free(ir_text);
		remove(temp_path);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open temporary C ABI source");
		return false;
	}
	if (!write_c_abi_library_file(out, ir_text, exports, export_count, err)) {
		fclose(out);
		free(ir_text);
		remove(temp_path);
		return false;
	}
	if (fclose(out) != 0) {
		free(ir_text);
		remove(temp_path);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close temporary C ABI source");
		return false;
	}
	free(ir_text);
	s_source_root = getenv("S_SOURCE_ROOT");
	if (!s_source_root) s_source_root = ".";
#if defined(__APPLE__)
	shared_flag = "-dynamiclib";
#else
	shared_flag = "-shared";
#endif
	snprintf(command, sizeof(command),
		"gcc -std=c11 -O2 -fPIC -fvisibility=hidden %s -Wall -Wextra -Werror -DSEED_COMPILE_ONLY -I %s/src/cmd/compile/seed -o %s %s "
		"%s/src/cmd/compile/seed/runtime/runtime.c %s/src/cmd/compile/seed/error/error.c "
		"%s/src/cmd/compile/seed/code/native_backend.c %s/src/cmd/compile/seed/lexical/lexer.c "
		"%s/src/cmd/compile/seed/syntax/parser.c %s/src/cmd/compile/seed/semantic/analyzer.c "
		"%s/src/cmd/compile/seed/intermediate/ir.c %s/src/cmd/compile/seed/code/generator.c "
		"%s/src/cmd/compile/seed/bootstrap/bootstrap.c %s/src/cmd/compile/seed/s_seed.c",
		shared_flag, s_source_root, output_library_path, temp_path,
		s_source_root, s_source_root, s_source_root, s_source_root,
		s_source_root, s_source_root, s_source_root, s_source_root,
		s_source_root, s_source_root);
	rc = system(command);
	remove(temp_path);
	if (rc != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "C ABI shared library generation command failed");
		return false;
	}
	return true;
}
