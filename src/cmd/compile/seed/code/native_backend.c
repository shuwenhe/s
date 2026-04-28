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
		"#include \"runtime/memory.h\"\n"
		"#include \"error/error.h\"\n\n"
		"static void print_compile_error(const compile_error *err) {\n"
		"    if (!err || !error_is_set(err)) {\n"
		"        return;\n"
		"    }\n"
		"    fprintf(stderr, \"error[%%d] at %%zu:%%zu: %%s\\n\", (int)err->code, err->line, err->column, err->message);\n"
		"}\n\n") < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to write generated C source");
		return false;
	}

	if (!write_escaped_ir(out, ir_text, err)) {
		return false;
	}

	if (fprintf(out,
		"\nint main(int argc, char **argv) {\n"
		"    long ret = 0;\n"
		"    compile_error err;\n"
		"    error_clear(&err);\n"
		"    if (!runtime_execute_text_with_argv(embedded_ir, \"main\", &ret, &err, argc, argv)) {\n"
		"        print_compile_error(&err);\n"
		"        return 1;\n"
		"    }\n"
		"    return (int)ret;\n"
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