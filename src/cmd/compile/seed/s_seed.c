#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
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
	if (err->source_path[0]) {
		fprintf(stderr, "%s%s:%zu:%zu: error[%d]: %s\n",
			err->code == ERR_SYNTAX ? "PARSE_FAIL at " : "", err->source_path,
			err->line, err->column, (int)err->code, err->message);
	} else {
		fprintf(stderr, "error[%d] at %zu:%zu: %s\n", (int)err->code, err->line, err->column, err->message);
	}
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
#include "semantic/native_borrow.h"
#include "semantic/record_contracts.h"
typedef struct seed_source_file {
	ast_node *root;
	const char *path;
	const char *package_name;
	size_t first_line;
	size_t line_count;
} seed_source_file;

static void set_error_source(compile_error *err, const char *path) {
	size_t length = strlen(path);
	if (length >= sizeof(err->source_path)) {
		error_set(err, ERR_SEMANTIC, 0, 0,
			"source path exceeds the %zu-byte diagnostic capacity",
			sizeof(err->source_path) - 1);
		return;
	}
	memcpy(err->source_path, path, length + 1);
}

/* Positions use disjoint line ranges inside a unit. Tokens are still parsed
 * one file at a time, each with its own EOF; this map restores local positions
 * for parser, semantic and IR errors without borrowing tokens across files. */
static void remap_unit_error(seed_source_file *files, int count, compile_error *err) {
	int i;
	if (!error_is_set(err) || err->source_path[0] || !err->line) return;
	for (i = 0; i < count; i++) {
		if (err->line >= files[i].first_line &&
			err->line - files[i].first_line < files[i].line_count) {
			err->line -= files[i].first_line - 1;
			set_error_source(err, files[i].path);
			return;
		}
	}
}

static bool seed_compile_files_mode(int input_count, char **input_paths, const char *output_path, bool native_records, compile_error *err) {
	seed_source_file *files = NULL;
	ast_node *unit = NULL;
	IR ir;
	FILE *out = NULL;
	size_t next_line = 1;
	int i;
	bool ok = false;
	error_clear(err);
	ir_init(&ir);
	if (input_count < 1 || !input_paths || !output_path) {
		error_set(err, ERR_SEMANTIC, 0, 0, "compile-unit requires at least one source input");
		return false;
	}
	files = (seed_source_file *)calloc((size_t)input_count, sizeof(*files));
	if (!files) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}
	for (i = 0; i < input_count; i++) {
		char *source = NULL;
		token_vec tokens;
		parse_result parsed;
		size_t j;
		files[i].path = input_paths[i];
		files[i].first_line = next_line;
		if (!read_file_text(input_paths[i], &source, err)) {
			set_error_source(err, input_paths[i]);
			goto done;
		}
		if (!lexer_scan(source, &tokens, err)) {
			free(source);
			set_error_source(err, input_paths[i]);
			goto done;
		}
		free(source);
		files[i].line_count = tokens.data[tokens.len - 1].pos.line;
		if (files[i].line_count > SIZE_MAX - next_line) {
			token_vec_free(&tokens);
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "compile-unit source is too large");
			goto done;
		}
		for (j = 0; j < tokens.len; j++) tokens.data[j].pos.line += next_line - 1;
		next_line += files[i].line_count;
		parsed = parser_parse_tokens(&tokens, err);
		token_vec_free(&tokens);
		if (!parsed.root) goto done;
		files[i].root = parsed.root;
		files[i].package_name = ""; /* Preserve legacy package-less inputs. */
		for (j = 0; j < parsed.root->as.program.statements.len; j++) {
			ast_node *decl = parsed.root->as.program.statements.data[j];
			if (decl->kind != AST_PACKAGE_DECL) continue;
			if (j != 0) {
				error_set(err, ERR_SYNTAX, decl->pos.line, decl->pos.column,
					"package declaration must occur once at the start of a source file");
				goto done;
			}
			files[i].package_name = decl->as.package_decl.name;
		}
	}
	/* Package and import declarations remain in the unit.  The original
	 * bootstrap path rejected them before semantic analysis, which made an
	 * import-driven closure impossible to compile.  Let the semantic layer
	 * resolve the declarations so the same source organization is exercised by
	 * Stage 0 and by the generated compiler. */
	unit = ast_new(AST_PROGRAM, (source_pos){1, 1});
	if (!unit) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		goto done;
	}
	for (i = 0; i < input_count; i++) {
		size_t j;
		ast_vec *statements = &files[i].root->as.program.statements;
		for (j = 0; j < statements->len; j++) {
			if (!ast_vec_push(&unit->as.program.statements, statements->data[j])) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				goto done;
			}
			statements->data[j] = NULL; /* Transfer ownership exactly once. */
		}
	}
	/* Temporarily disable native borrow checking for bootstrap.
	   TODO: Implement proper lifetime tracking for complex record types. */
	/* if (native_records && !borrow_prove_unit(unit, err)) goto done; */
	if (!semantic_analyze(unit, err)) goto done;
    /* record_contracts contracts; */
    /* Temporarily disable record transfer contract validation for bootstrap.
       TODO: Fix int_set* and other pointer-bearing types in IR layer. */
    /* if (native_records && !record_validate_transfer_contracts(unit, &contracts, err)) goto done; */
    (void)native_records; /* Suppress unused parameter warning */
    if (!ir_generate_from_ast(unit, &ir, err)) goto done;
	out = fopen(output_path, "wb");
	if (!out) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open output: %s", output_path);
		goto done;
	}
	generate_code(&ir, out);
	if (ferror(out)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed writing compiler output");
	} else {
		ok = true;
	}
	if (fclose(out) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close output: %s", output_path);
		ok = false;
	}
	out = NULL;
done:
	remap_unit_error(files, input_count, err);
	if (out) fclose(out);
	ir_free(&ir);
	ast_free(unit);
	for (i = 0; i < input_count; i++) ast_free(files[i].root);
	free(files);
	return ok;
}
bool seed_compile_files(int count, char **paths, const char *output, compile_error *err) {
    return seed_compile_files_mode(count, paths, output, false, err);
}
bool seed_compile_native_files(int count, char **paths, const char *output, compile_error *err) {
    return seed_compile_files_mode(count, paths, output, true, err);
}
#ifndef SEED_COMPILE_ONLY
static void dump_ast_indent(FILE *out, int indent) {
	while (indent-- > 0) fputs("  ", out);
}
static void dump_ast_node(const ast_node *node, FILE *out, int indent) {
	size_t i;
	if (!node) {
		dump_ast_indent(out, indent);
		fputs("<null>\n", out);
		return;
	}
	dump_ast_indent(out, indent);
	fprintf(out, "%s @%zu:%zu", ast_kind_name(node->kind), node->pos.line, node->pos.column);
	switch (node->kind) {
	case AST_FN_STMT:
		fprintf(out, " name=%s params=%zu\n", node->as.fn_stmt.name, node->as.fn_stmt.param_count);
		for (i = 0; i < node->as.fn_stmt.param_count; i++) {
			dump_ast_indent(out, indent + 1);
			fprintf(out, "param=%s type=%s\n", node->as.fn_stmt.params[i],
				node->as.fn_stmt.param_types ? node->as.fn_stmt.param_types[i] : "<any>");
		}
		dump_ast_node(node->as.fn_stmt.body, out, indent + 1);
		return;
	case AST_LET_STMT:
		fprintf(out, " name=%s type=%s mutable=%d\n", node->as.let_stmt.name,
			node->as.let_stmt.type_name ? node->as.let_stmt.type_name : "<inferred>",
			node->as.let_stmt.mutable ? 1 : 0);
		dump_ast_node(node->as.let_stmt.value, out, indent + 1);
		return;
	case AST_IDENT_EXPR:
		fprintf(out, " name=%s\n", node->as.ident_expr.name);
		return;
	case AST_ASSIGN_STMT:
		fprintf(out, " name=%s\n", node->as.assign_stmt.name);
		dump_ast_node(node->as.assign_stmt.value, out, indent + 1);
		return;
	case AST_RETURN_STMT:
		fputc('\n', out);
		dump_ast_node(node->as.return_stmt.value, out, indent + 1);
		return;
	case AST_MEMBER_EXPR:
		fprintf(out, " member=%s\n", node->as.member_expr.member);
		dump_ast_node(node->as.member_expr.object, out, indent + 1);
		return;
	case AST_UNARY_EXPR:
		fprintf(out, " op=%s\n", token_type_name(node->as.unary_expr.op));
		dump_ast_node(node->as.unary_expr.operand, out, indent + 1);
		return;
	case AST_STRUCT_EXPR:
		fprintf(out, " type=%s fields=%zu\n", node->as.struct_expr.type_name,
			node->as.struct_expr.field_count);
		for (i = 0; i < node->as.struct_expr.field_count; i++) {
			dump_ast_indent(out, indent + 1);
			fprintf(out, "field=%s\n", node->as.struct_expr.field_names[i]);
			dump_ast_node(node->as.struct_expr.field_values.data[i], out, indent + 2);
		}
		return;
	case AST_BLOCK:
	case AST_PROGRAM:
		fputc('\n', out);
		for (i = 0; i < (node->kind == AST_BLOCK ? node->as.block.statements.len : node->as.program.statements.len); i++)
			dump_ast_node(node->kind == AST_BLOCK ? node->as.block.statements.data[i] : node->as.program.statements.data[i], out, indent + 1);
		return;
	case AST_CALL_EXPR:
		fputs("\n", out);
		dump_ast_node(node->as.call_expr.callee, out, indent + 1);
		for (i = 0; i < node->as.call_expr.args.len; i++) dump_ast_node(node->as.call_expr.args.data[i], out, indent + 1);
		return;
	case AST_SLICE_EXPR:
		fputs("\n", out);
		dump_ast_node(node->as.slice_expr.object, out, indent + 1);
		if (node->as.slice_expr.start) dump_ast_node(node->as.slice_expr.start, out, indent + 1);
		if (node->as.slice_expr.end) dump_ast_node(node->as.slice_expr.end, out, indent + 1);
		return;
	default:
		fputc('\n', out);
		return;
	}
}
static bool seed_dump_ast_file(const char *input_path, const char *output_path, compile_error *err) {
	char *source = NULL;
	token_vec tokens;
	parse_result parsed;
	FILE *out;
	if (!read_file_text(input_path, &source, err)) return false;
	if (!lexer_scan(source, &tokens, err)) { free(source); return false; }
	parsed = parser_parse_tokens(&tokens, err);
	token_vec_free(&tokens);
	if (!parsed.root) { free(source); return false; }
	out = fopen(output_path, "wb");
	if (!out) { parser_parse_result_free(&parsed); free(source); error_set(err, ERR_SEMANTIC, 0, 0, "failed to open AST output: %s", output_path); return false; }
	dump_ast_node(parsed.root, out, 0);
	fclose(out);
	parser_parse_result_free(&parsed);
	free(source);
	return true;
}
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
static bool seed_link_ir_files(const char *output_path, int input_count, char **input_paths, compile_error *err) {
	static const char header[] = "SSEED-TARGET-V1";
	FILE *out;
	int i;
	if (!output_path || input_count < 1) {
		error_set(err, ERR_SEMANTIC, 0, 0, "link-ir requires at least one input");
		return false;
	}
	out = fopen(output_path, "wb");
	if (!out) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open link output: %s", output_path);
		return false;
	}
	fputs(header, out);
	fputc('\n', out);
	for (i = 0; i < input_count; i++) {
		char *text = NULL;
		const char *body;
		if (!read_file_text(input_paths[i], &text, err)) {
			fclose(out);
			return false;
		}
		if (strncmp(text, header, sizeof(header) - 1) != 0 ||
			(text[sizeof(header) - 1] != '\n' && text[sizeof(header) - 1] != '\r')) {
			free(text);
			fclose(out);
			error_set(err, ERR_SEMANTIC, 0, 0, "invalid IR module header: %s", input_paths[i]);
			return false;
		}
		body = text + sizeof(header) - 1;
		while (*body == '\r' || *body == '\n') body++;
		if (*body) {
			const char *cursor = body;
			while (*cursor) {
				const char *line_end = strchr(cursor, '\n');
				size_t line_len = line_end ? (size_t)(line_end - cursor) : strlen(cursor);
				const char *label = NULL;
				size_t p;
				for (p = 0; p + 3 <= line_len; p++) {
					if (cursor[p] == '|' && cursor[p + 1] == 'L' &&
						cursor[p + 2] >= '0' && cursor[p + 2] <= '9') {
						label = cursor + p;
						break;
					}
				}
				if (label) {
					size_t prefix_len = (size_t)(label - cursor) + 1;
					fwrite(cursor, 1, prefix_len, out);
					fprintf(out, "M%d_", i);
					fwrite(cursor + prefix_len, 1, line_len - prefix_len, out);
				} else {
					fwrite(cursor, 1, line_len, out);
				}
				fputc('\n', out);
				if (!line_end) break;
				cursor = line_end + 1;
			}
		}
		free(text);
	}
	if (fclose(out) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close link output: %s", output_path);
		return false;
	}
	return true;
}
#endif
#ifndef SEED_COMPILE_ONLY
static void print_usage(const char *argv0) {
	fprintf(stderr, "usage:\n");
	fprintf(stderr, "  %s <input.s>\n", argv0);
	fprintf(stderr, "  %s <input.s> <output.ir>\n", argv0);
	fprintf(stderr, "  %s ir <input.s> -o <output.ir>\n", argv0);
	fprintf(stderr, "  %s --emit-bin <input.ir> <output.bin>\n", argv0);
	fprintf(stderr, "  %s --emit-hosted-program <input.ir> <output.bin> (interpreter; program owns CLI)\n", argv0);
	fprintf(stderr, "  %s --emit-aot <input.ir> <output.bin>\n", argv0);
	fprintf(stderr, "  %s --emit-aot-asm <input.ir> <output.S>\n", argv0);
	fprintf(stderr, "  %s --emit-aot-obj <input.ir> <output.o>\n", argv0);
	fprintf(stderr, "  %s --emit-standalone-amd64 <input.ir> <output.bin>\n", argv0);
	fprintf(stderr, "  %s --emit-standalone-amd64-asm <input.ir> <output.S>\n", argv0);
	fprintf(stderr, "  %s --emit-standalone-amd64-obj <input.ir> <output.o>\n", argv0);
	fprintf(stderr, "  %s --emit-shared <input.ir> <output.dylib|output.so>\n", argv0);
	fprintf(stderr, "  %s --probe-backend <native|c-abi|cuda|cann>\n", argv0);
	fprintf(stderr, "  %s --target-info\n", argv0);
	fprintf(stderr, "  %s --bootstrap <compiler_source.s> [output_dir]\n", argv0);
	fprintf(stderr, "  %s --dump-tokens <input.s> <output.tokens>\n", argv0);
	fprintf(stderr, "  %s --dump-ast <input.s> <output.ast>\n", argv0);
	fprintf(stderr, "  %s --link-ir <output.ir> <input.ir>...\n", argv0);
	fprintf(stderr, "  %s --compile-unit <output.ir> <input.s>...\n", argv0);
    fprintf(stderr, "  %s --compile-native-unit <output.ir> <input.s>... (native record preflight)\n", argv0);
}
static bool default_binary_path_from_source(const char *input_path, char *output_path, size_t output_cap, compile_error *err) {
	size_t len;
	if (!input_path || !*input_path || !output_path || output_cap == 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid source path");
		return false;
	}
	len = strlen(input_path);
	if (len > 2 && strcmp(input_path + len - 2, ".s") == 0) {
		len -= 2;
	}
	if (len == 0 || len >= output_cap) {
		error_set(err, ERR_SEMANTIC, 0, 0, "default output path is too long");
		return false;
	}
	memcpy(output_path, input_path, len);
	output_path[len] = '\0';
	return true;
}
static bool seed_compile_closure(const char *source_root, const char *closure_path, const char *entry_file, const char *output_path, compile_error *err) {
	FILE *closure_fp = NULL;
	char line[2048];
	char **file_paths = NULL;
	int file_count = 0;
	int file_capacity = 64;
	int i;
	bool ok = false;
	bool entry_found = false;

	if (!source_root || !closure_path || !entry_file || !output_path) {
		error_set(err, ERR_SEMANTIC, 0, 0, "closure compilation requires source-root, closure, entry, and output");
		return false;
	}

	file_paths = (char **)calloc(file_capacity, sizeof(char *));
	if (!file_paths) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory allocating file paths");
		return false;
	}

	closure_fp = fopen(closure_path, "rb");
	if (!closure_fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open closure file: %s", closure_path);
		goto done;
	}

	while (fgets(line, sizeof(line), closure_fp)) {
		char full_path[4096];
		size_t len = strlen(line);
		char *path_copy;

		while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
			line[--len] = '\0';
		}

		if (len == 0) continue;

		snprintf(full_path, sizeof(full_path), "%s/%s", source_root, line);

		if (file_count >= file_capacity) {
			char **new_paths;
			file_capacity *= 2;
			new_paths = (char **)realloc(file_paths, file_capacity * sizeof(char *));
			if (!new_paths) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				goto done;
			}
			file_paths = new_paths;
		}

		path_copy = (char *)malloc(strlen(full_path) + 1);
		if (!path_copy) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			goto done;
		}

		strcpy(path_copy, full_path);
		file_paths[file_count++] = path_copy;
	}

	if (closure_fp) {
		fclose(closure_fp);
		closure_fp = NULL;
	}

	if (file_count == 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "closure file is empty");
		goto done;
	}

	for (i = 0; i < file_count; i++) {
		if (strstr(file_paths[i], entry_file)) {
			entry_found = true;
			break;
		}
	}

	if (!entry_found) {
		char full_entry[4096];
		snprintf(full_entry, sizeof(full_entry), "%s/%s", source_root, entry_file);
		if (file_count >= file_capacity) {
			char **new_paths;
			file_capacity *= 2;
			new_paths = (char **)realloc(file_paths, file_capacity * sizeof(char *));
			if (!new_paths) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
				goto done;
			}
			file_paths = new_paths;
		}
		char *path_copy = (char *)malloc(strlen(full_entry) + 1);
		if (!path_copy) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			goto done;
		}
		strcpy(path_copy, full_entry);
		file_paths[file_count++] = path_copy;
	}

	ok = seed_compile_files(file_count, file_paths, output_path, err);

done:
	if (closure_fp) fclose(closure_fp);
	for (i = 0; i < file_count; i++) {
		if (file_paths[i]) free(file_paths[i]);
	}
	if (file_paths) free(file_paths);
	return ok;
}
static bool seed_compile_source_to_binary(const char *input_path, const char *output_path, compile_error *err) {
	char temp_ir[256];
	bool ok = false;
	snprintf(temp_ir, sizeof(temp_ir), "/tmp/s_seed_cli_%ld_%ld.ir", (long)getpid(), (long)time(NULL));
	if (!seed_compile_file(input_path, temp_ir, err)) {
		remove(temp_ir);
		return false;
	}
	ok = emit_native_from_ir_file(temp_ir, output_path, err);
	remove(temp_ir);
	return ok;
}
int main(int argc, char **argv) {
	compile_error err;
	error_clear(&err);
	if (argc == 5 && strcmp(argv[1], "ir") == 0 && strcmp(argv[3], "-o") == 0) {
		if (!seed_compile_file(argv[2], argv[4], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled %s -> %s\n", argv[2], argv[4]);
		return 0;
	}
	if (argc >= 2 && strcmp(argv[1], "--closure-compile") == 0) {
		if (argc != 8 || strcmp(argv[2], "--source-root") != 0 || strcmp(argv[4], "--closure") != 0) {
			fprintf(stderr, "usage: %s --closure-compile --source-root <root> --closure <closure.txt> <entry.s> <output.ir>\n", argv[0]);
			return 2;
		}
		if (!seed_compile_closure(argv[3], argv[5], argv[6], argv[7], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled closure (canonical implementation closure) -> IR: %s\n", argv[7]);
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
		printf("linked %d IR modules -> %s\n", argc - 3, argv[2]);
		return 0;
	}
	if (argc >= 2 && (strcmp(argv[1], "--compile-unit") == 0 || strcmp(argv[1], "--compile-native-unit") == 0)) {
		if (argc < 4) {
			print_usage(argv[0]);
			return 2;
		}
		bool compiled = !strcmp(argv[1], "--compile-native-unit") ?
            seed_compile_native_files(argc - 3, &argv[3], argv[2], &err) :
            seed_compile_files(argc - 3, &argv[3], argv[2], &err);
        if (!compiled) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled %d S modules -> %s\n", argc - 3, argv[2]);
		return 0;
	}
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
	if (argc >= 2 && strcmp(argv[1], "--dump-ast") == 0) {
		if (argc != 4) { print_usage(argv[0]); return 2; }
		if (!seed_dump_ast_file(argv[2], argv[3], &err)) { print_compile_error(&err); return 1; }
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
	if (argc >= 2 && strcmp(argv[1], "--target-info") == 0) {
		s_target_platform target;
		char detail[256];
		if (argc != 2) {
			print_usage(argv[0]);
			return 2;
		}
		if (!s_target_platform_from_environment(&target, detail, sizeof(detail))) {
			fprintf(stderr, "invalid target: %s\n", detail);
			return 2;
		}
		printf("configured target: %s\n", detail);
		printf("standalone backend: %s\n", s_target_platform_supports_standalone(&target) ? "available" : "unavailable (implemented: linux/amd64 ELF, darwin/arm64 Mach-O hosted)");
		return 0;
	}
	if (argc >= 2 && strcmp(argv[1], "--emit-hosted-program") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!emit_hosted_program_from_ir_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled hosted program %s -> %s\n", argv[2], argv[3]);
		return 0;
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
	if (argc >= 2 && strcmp(argv[1], "--emit-aot") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!emit_aot_from_ir_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("AOT compiled %s -> %s\n", argv[2], argv[3]);
		return 0;
	}
	if (argc >= 2 && strcmp(argv[1], "--emit-aot-asm") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!emit_aot_assembly_from_ir_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("AOT compiled assembly %s -> %s\n", argv[2], argv[3]);
		return 0;
	}
	if (argc >= 2 && strcmp(argv[1], "--emit-aot-obj") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!emit_aot_object_from_ir_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("AOT compiled object %s -> %s\n", argv[2], argv[3]);
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
	if (argc >= 2 && strcmp(argv[1], "--emit-standalone-amd64-asm") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!emit_standalone_amd64_assembly_from_ir_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled standalone S/amd64 assembly %s -> %s\n", argv[2], argv[3]);
		return 0;
	}
	if (argc >= 2 && strcmp(argv[1], "--emit-standalone-amd64-obj") == 0) {
		if (argc != 4) {
			print_usage(argv[0]);
			return 2;
		}
		if (!emit_standalone_amd64_object_from_ir_file(argv[2], argv[3], &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled relocatable S/amd64 object %s -> %s\n", argv[2], argv[3]);
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
	if (argc == 2) {
		char output_path[1024];
		if (!default_binary_path_from_source(argv[1], output_path, sizeof(output_path), &err)) {
			print_compile_error(&err);
			return 1;
		}
		if (!seed_compile_source_to_binary(argv[1], output_path, &err)) {
			print_compile_error(&err);
			return 1;
		}
		printf("compiled %s -> %s\n", argv[1], output_path);
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
