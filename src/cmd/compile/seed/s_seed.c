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
