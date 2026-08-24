#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "code/target.h"
#include "error/error.h"
#include "intermediate/ir.h"
#include "lexical/token.h"
#include "semantic/scope.h"
#include "syntax/ast.h"

bool seed_bootstrap_two_stage_check(const char *compiler_source_path, const char *output_dir, compile_error *err);

#ifndef SEED_COMPILE_ONLY
static void print_compile_error(const compile_error *err) {
	if (!err || !error_is_set(err)) {
		return;
	}
	fprintf(stderr, "error[%d] at %zu:%zu: %s\n", (int)err->code, err->line, err->column, err->message);
}
#endif

static bool read_file_text(const char *path, char **out_text, compile_error *err) {
	FILE *fp;
	long n;
	size_t read_n;
	char *buf;

	*out_text = NULL;
	fp = fopen(path, "rb");
	if (!fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open input: %s", path);
		return false;
	}
	if (fseek(fp, 0, SEEK_END) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to seek input: %s", path);
		return false;
	}
	n = ftell(fp);
	if (n < 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to tell input size: %s", path);
		return false;
	}
	if (fseek(fp, 0, SEEK_SET) != 0) {
		fclose(fp);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to rewind input: %s", path);
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
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to read input: %s", path);
		return false;
	}
	buf[n] = '\0';
	*out_text = buf;
	return true;
}

bool seed_compile_source_text(const char *source_text, FILE *output, compile_error *err) {
	token_vec tokens;
	parse_result parsed;
	IR ir;
	bool ok = false;

	error_clear(err);
	if (!source_text || !output) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid compile input");
		return false;
	}

	if (!lexer_scan(source_text, &tokens, err)) {
		return false;
	}

	parsed = parser_parse_tokens(&tokens, err);
	token_vec_free(&tokens);
	if (!parsed.root) {
		return false;
	}

	if (!semantic_analyze(parsed.root, err)) {
		parser_parse_result_free(&parsed);
		return false;
	}

	ir_init(&ir);
	if (!ir_generate_from_ast(parsed.root, &ir, err)) {
		ir_free(&ir);
		parser_parse_result_free(&parsed);
		return false;
	}

	generate_code(&ir, output);
	if (ferror(output)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing compiler output");
	} else {
		ok = true;
	}

	ir_free(&ir);
	parser_parse_result_free(&parsed);
	return ok;
}

bool seed_compile_file(const char *input_path, const char *output_path, compile_error *err) {
	char *source_text = NULL;
	FILE *out;
	bool ok;

	if (!read_file_text(input_path, &source_text, err)) {
		return false;
	}

	out = fopen(output_path, "wb");
	if (!out) {
		free(source_text);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open output: %s", output_path);
		return false;
	}

	ok = seed_compile_source_text(source_text, out, err);
	free(source_text);
	if (fclose(out) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close output: %s", output_path);
		return false;
	}
	return ok;
}

#ifndef SEED_COMPILE_ONLY
static void write_hex(FILE *out, const char *text) {
	static const char digits[] = "0123456789abcdef";
	const unsigned char *p = (const unsigned char *)(text ? text : "");
	while (*p) {
		fputc(digits[*p >> 4], out);
		fputc(digits[*p & 15], out);
		p++;
	}
}

static bool seed_dump_tokens_file(const char *input_path, const char *output_path, compile_error *err) {
	char *source_text = NULL;
	token_vec tokens;
	FILE *out;
	size_t i;
	if (!read_file_text(input_path, &source_text, err)) return false;
	out = fopen(output_path, "wb");
	if (!out) {
		free(source_text);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open token output: %s", output_path);
		return false;
	}
	if (!lexer_scan(source_text, &tokens, err)) {
		const char *code = err->code == ERR_ILLEGAL_CHAR ? "ILLEGAL_CHAR" :
			err->code == ERR_UNTERMINATED_STRING ? "UNTERMINATED_STRING" : "SYNTAX";
		fprintf(out, "ERROR|%s|%zu|%zu|%s\n", code, err->line, err->column, err->message);
		fclose(out);
		free(source_text);
		error_clear(err);
		return true;
	}
	for (i = 0; i < tokens.len; i++) {
		fprintf(out, "%s|", token_type_name(tokens.data[i].type));
		write_hex(out, tokens.data[i].lexeme);
		fprintf(out, "|%zu|%zu\n", tokens.data[i].pos.line, tokens.data[i].pos.column);
	}
	if (fclose(out) != 0) {
		token_vec_free(&tokens);
		free(source_text);
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close token output: %s", output_path);
		return false;
	}
	token_vec_free(&tokens);
	free(source_text);
	return true;
}

typedef struct linked_function_names {
	char **data;
	size_t len;
	size_t cap;
} linked_function_names;

static void linked_function_names_free(linked_function_names *names) {
	size_t i;
	for (i = 0; i < names->len; i++) free(names->data[i]);
	free(names->data);
	memset(names, 0, sizeof(*names));
}

static bool linked_function_add(linked_function_names *names, const char *name, compile_error *err) {
	size_t i;
	char *copy;
	for (i = 0; i < names->len; i++) {
		if (strcmp(names->data[i], name) == 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "duplicate linked function: %s", name);
			return false;
		}
	}
	if (names->len == names->cap) {
		size_t next_cap = names->cap ? names->cap * 2 : 32;
		char **next = (char **)realloc(names->data, next_cap * sizeof(*next));
		if (!next) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return false;
		}
		names->data = next;
		names->cap = next_cap;
	}
	copy = (char *)malloc(strlen(name) + 1);
	if (!copy) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}
	strcpy(copy, name);
	names->data[names->len++] = copy;
	return true;
}

static bool linked_ir_write_line(FILE *out, const char *line, size_t module_index, compile_error *err) {
	const char *first_sep;
	const char *second_sep;
	size_t op_len;
	bool is_label_record;

	first_sep = strchr(line, '|');
	if (!first_sep) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid IR record without fields");
		return false;
	}
	op_len = (size_t)(first_sep - line);
	is_label_record = (op_len == 5 && strncmp(line, "LABEL", 5) == 0) ||
		(op_len == 4 && strncmp(line, "JUMP", 4) == 0) ||
		(op_len == 13 && strncmp(line, "JUMP_IF_FALSE", 13) == 0);
	if (!is_label_record) {
		if (fprintf(out, "%s\n", line) < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "failed writing linked IR");
			return false;
		}
		return true;
	}
	second_sep = strchr(first_sep + 1, '|');
	if (!second_sep) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid control-flow IR record");
		return false;
	}
	if (fprintf(out, "%.*s|m%zu_%.*s%s\n", (int)op_len, line, module_index,
		(int)(second_sep - first_sep - 1), first_sep + 1, second_sep) < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing linked IR");
		return false;
	}
	return true;
}

static bool seed_link_ir_files(const char *output_path, int input_count, char **input_paths, compile_error *err) {
	FILE *out = NULL;
	linked_function_names names = {0};
	bool ok = false;
	int input_index;

	if (input_count < 1) {
		error_set(err, ERR_SEMANTIC, 0, 0, "at least one IR input is required");
		return false;
	}
	out = fopen(output_path, "wb");
	if (!out) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open linked output: %s", output_path);
		return false;
	}
	fputs("SSEED-TARGET-V1\n", out);
	for (input_index = 0; input_index < input_count; input_index++) {
		char *text = NULL;
		char *cursor;
		bool first_line = true;
		if (!read_file_text(input_paths[input_index], &text, err)) goto done;
		cursor = text;
		while (*cursor) {
			char *line = cursor;
			char *newline = strchr(cursor, '\n');
			if (newline) {
				*newline = '\0';
				cursor = newline + 1;
			} else {
				cursor += strlen(cursor);
			}
			if (first_line) {
				first_line = false;
				if (strcmp(line, "SSEED-TARGET-V1") != 0) {
					error_set(err, ERR_SEMANTIC, 1, 1, "invalid target header in %s", input_paths[input_index]);
					free(text);
					goto done;
				}
				continue;
			}
			if (strncmp(line, "FUNC_BEGIN|", 11) == 0) {
				const char *name = line + 11;
				const char *sep = strchr(name, '|');
				char function_name[256];
				size_t name_len;
				if (!sep || (name_len = (size_t)(sep - name)) == 0 || name_len >= sizeof(function_name)) {
					error_set(err, ERR_SEMANTIC, 0, 0, "invalid linked function record in %s", input_paths[input_index]);
					free(text);
					goto done;
				}
				memcpy(function_name, name, name_len);
				function_name[name_len] = '\0';
				if (!linked_function_add(&names, function_name, err)) {
					free(text);
					goto done;
				}
			}
			if (*line && !linked_ir_write_line(out, line, (size_t)input_index, err)) {
				free(text);
				goto done;
			}
		}
		free(text);
	}
	if (ferror(out)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing linked output: %s", output_path);
		goto done;
	}
	ok = true;

done:
	if (out && fclose(out) != 0 && ok) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close linked output: %s", output_path);
		ok = false;
	}
	linked_function_names_free(&names);
	if (!ok) remove(output_path);
	return ok;
}
#endif

#ifndef SEED_COMPILE_ONLY
static void print_usage(const char *argv0) {
	fprintf(stderr, "usage:\n");
	fprintf(stderr, "  %s <input.s> <output.ir>\n", argv0);
	fprintf(stderr, "  %s --emit-bin <input.ir> <output.bin>\n", argv0);
	fprintf(stderr, "  %s --emit-standalone-amd64 <input.ir> <output.bin>\n", argv0);
	fprintf(stderr, "  %s --emit-shared <input.ir> <output.dylib|output.so>\n", argv0);
	fprintf(stderr, "  %s --probe-backend <native|c-abi|cuda|cann>\n", argv0);
	fprintf(stderr, "  %s --bootstrap <compiler_source.s> [output_dir]\n", argv0);
	fprintf(stderr, "  %s --dump-tokens <input.s> <output.tokens>\n", argv0);
	fprintf(stderr, "  %s --link-ir <output.ir> <input.ir>...\n", argv0);
}

int main(int argc, char **argv) {
	compile_error err;
	error_clear(&err);

	if (argc >= 2 && strcmp(argv[1], "--dump-tokens") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!seed_dump_tokens_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		return 0;
	}

	if (argc >= 2 && strcmp(argv[1], "--link-ir") == 0) {
		if (argc < 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!seed_link_ir_files(argv[2], argc - 3, &argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("linked %d modules -> %s\n", argc - 3, argv[2]);
		return 0;
	}

	if (argc >= 2 && strcmp(argv[1], "--probe-backend") == 0) {
		s_target_backend backend;
		char detail[512];
		bool available;
		if (argc != 3) {
			print_usage(argv[0]);
			return 2;
		}
		if (strcmp(argv[2], "native") == 0) backend = S_TARGET_NATIVE;
		else if (strcmp(argv[2], "c-abi") == 0) backend = S_TARGET_C_ABI;
		else if (strcmp(argv[2], "cuda") == 0) backend = S_TARGET_CUDA;
		else if (strcmp(argv[2], "cann") == 0) backend = S_TARGET_CANN;
		else {
			fprintf(stderr, "unknown backend: %s\n", argv[2]);
			return 2;
		}
		available = s_target_backend_probe(backend, detail, sizeof(detail));
		printf("%s: %s\n", s_target_backend_name(backend), detail);
		return available ? 0 : 3;
	}

	if (argc >= 2 && strcmp(argv[1], "--emit-bin") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!emit_native_from_ir_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled %s -> %s\n", argv[2], argv[3]);
		return 0;
	}

	if (argc >= 2 && strcmp(argv[1], "--emit-standalone-amd64") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!emit_standalone_amd64_from_ir_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled standalone Linux/amd64 %s -> %s\n", argv[2], argv[3]);
		return 0;
	}

	if (argc >= 2 && strcmp(argv[1], "--emit-shared") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!emit_c_abi_shared_from_ir_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled C ABI library %s -> %s\n", argv[2], argv[3]);
		return 0;
	}

	if (argc >= 2 && strcmp(argv[1], "--bootstrap") == 0) {
		const char *compiler_src;
		const char *out_dir = ".";
		if (argc < 3 || argc > 4) {
			print_usage(argv[0]);
			return 2;
		}
		compiler_src = argv[2];
		if (argc == 4) {
			out_dir = argv[3];
		}
		if (!seed_bootstrap_two_stage_check(compiler_src, out_dir, &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("bootstrap self-host check passed (stage2 IR == stage3 IR)\n");
		return 0;
	}

	if (argc != 3) {
		print_usage(argv[0]);
		return 2;
	}

	if (!seed_compile_file(argv[1], argv[2], &err)) {
		print_compile_error(&err);
		return 1;
	}

	printf("compiled %s -> %s\n", argv[1], argv[2]);
	return 0;
}
#endif
