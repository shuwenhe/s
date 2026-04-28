#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "../code/target.h"
#include "../error/error.h"
#include "../intermediate/ir.h"
#include "../lexical/token.h"
#include "../runtime/memory.h"
#include "../semantic/scope.h"
#include "../syntax/ast.h"

static bool expect_tokens(const token_vec *vec, const token_type *expected, size_t n) {
	size_t i;
	if (vec->len != n) {
		return false;
	}
	for (i = 0; i < n; i++) {
		if (vec->data[i].type != expected[i]) {
			return false;
		}
	}
	return true;
}

static bool test_let_statement(void) {
	const char *src = "let x = 42;";
	token_type expected[] = {
		TOKEN_LET,
		TOKEN_IDENTIFIER,
		TOKEN_ASSIGN,
		TOKEN_NUMBER,
		TOKEN_SEMICOLON,
		TOKEN_EOF,
	};
	token_vec tokens;
	compile_error err;
	bool ok = lexer_scan(src, &tokens, &err);
	if (!ok) {
		return false;
	}
	ok = expect_tokens(&tokens, expected, sizeof(expected) / sizeof(expected[0]));
	token_vec_free(&tokens);
	return ok;
}

static bool test_function_header(void) {
	const char *src = "fn add(a, b) { return a + b; }";
	token_type expected[] = {
		TOKEN_FN,
		TOKEN_IDENTIFIER,
		TOKEN_LPAREN,
		TOKEN_IDENTIFIER,
		TOKEN_COMMA,
		TOKEN_IDENTIFIER,
		TOKEN_RPAREN,
		TOKEN_LBRACE,
		TOKEN_RETURN,
		TOKEN_IDENTIFIER,
		TOKEN_PLUS,
		TOKEN_IDENTIFIER,
		TOKEN_SEMICOLON,
		TOKEN_RBRACE,
		TOKEN_EOF,
	};
	token_vec tokens;
	compile_error err;
	bool ok = lexer_scan(src, &tokens, &err);
	if (!ok) {
		return false;
	}
	ok = expect_tokens(&tokens, expected, sizeof(expected) / sizeof(expected[0]));
	token_vec_free(&tokens);
	return ok;
}

static bool test_illegal_char_error(void) {
	const char *src = "let x = @;";
	token_vec tokens;
	compile_error err;
	bool ok = lexer_scan(src, &tokens, &err);
	if (ok) {
		token_vec_free(&tokens);
		return false;
	}
	return err.code == ERR_ILLEGAL_CHAR;
}

static bool test_unterminated_string_error(void) {
	const char *src = "let s = \"abc";
	token_vec tokens;
	compile_error err;
	bool ok = lexer_scan(src, &tokens, &err);
	if (ok) {
		token_vec_free(&tokens);
		return false;
	}
	return err.code == ERR_UNTERMINATED_STRING;
}

static bool test_parser_let_and_precedence(void) {
	const char *src = "let x = 1 + 2 * 3;";
	token_vec tokens;
	compile_error err;
	parse_result result;
	ast_node *stmt;
	ast_node *expr;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}

	ok = result.root->kind == AST_PROGRAM && result.root->as.program.statements.len == 1;
	if (!ok) {
		parser_parse_result_free(&result);
		return false;
	}

	stmt = result.root->as.program.statements.data[0];
	ok = stmt->kind == AST_LET_STMT;
	if (!ok) {
		parser_parse_result_free(&result);
		return false;
	}

	expr = stmt->as.let_stmt.value;
	ok = expr->kind == AST_BINARY_EXPR && expr->as.binary_expr.op == TOKEN_PLUS;
	ok = ok && expr->as.binary_expr.right->kind == AST_BINARY_EXPR;
	ok = ok && expr->as.binary_expr.right->as.binary_expr.op == TOKEN_STAR;

	parser_parse_result_free(&result);
	return ok;
}

static bool test_parser_return_and_block(void) {
	const char *src = "{ let x = 1; return x; }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	ast_node *block_stmt;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}

	ok = result.root->kind == AST_PROGRAM && result.root->as.program.statements.len == 1;
	if (!ok) {
		parser_parse_result_free(&result);
		return false;
	}

	block_stmt = result.root->as.program.statements.data[0];
	ok = block_stmt->kind == AST_BLOCK && block_stmt->as.block.statements.len == 2;
	if (ok) {
		ok = block_stmt->as.block.statements.data[0]->kind == AST_LET_STMT;
	}
	if (ok) {
		ok = block_stmt->as.block.statements.data[1]->kind == AST_RETURN_STMT;
	}

	parser_parse_result_free(&result);
	return ok;
}

static bool test_parser_control_flow_and_function(void) {
	const char *src =
		"fn sum(a, b) { let i = 0; while (i < b) { i + 1; } return a + b; } "
		"for (let k = 0; k < 10; k + 1) { if (k == 3) { k + 1; } else { k + 2; } }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}

	ok = result.root->kind == AST_PROGRAM;
	ok = ok && result.root->as.program.statements.len == 2;
	if (ok) {
		ok = result.root->as.program.statements.data[0]->kind == AST_FN_STMT;
	}
	if (ok) {
		ok = result.root->as.program.statements.data[1]->kind == AST_FOR_STMT;
	}

	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_ok(void) {
	const char *src = "fn add(a, b) { let c = a + b; return c; }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = semantic_analyze(result.root, &err);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_undeclared_symbol(void) {
	const char *src = "fn main() { return x; }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_return_outside_function(void) {
	const char *src = "return 1;";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_call_arity_mismatch(void) {
	const char *src =
		"fn add(int a, int b) int { return a + b; } "
		"fn main() int { return add(1); }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_return_type_mismatch(void) {
	const char *src = "fn main() int { return \"oops\"; }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_call_arg_type_mismatch(void) {
	const char *src =
		"fn add(int a, int b) int { return a + b; } "
		"fn main() int { return add(1, \"x\"); }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_missing_return_path(void) {
	const char *src = "fn classify(int x) int { if (x > 0) { return 1; } }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_assignment_and_loop_control(void) {
	const char *src =
		"fn main() int { "
		"  let i = 0; "
		"  while i < 10 { "
		"    i = i + 1; "
		"    if i == 3 { continue; } "
		"    if i == 5 { break; } "
		"  } "
		"  return i; "
		"}";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = semantic_analyze(result.root, &err);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_bool_flow(void) {
	const char *src = "fn main() int { if !false && true { return 1; } return 0; }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = semantic_analyze(result.root, &err);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_unreachable_after_break(void) {
	const char *src =
		"fn main() int { "
		"  while true { "
		"    break; "
		"    let x = 1; "
		"  } "
		"  return 0; "
		"}";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	ok = ok && strstr(err.message, "after break") != NULL;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_unreachable_after_continue(void) {
	const char *src =
		"fn main() int { "
		"  while true { "
		"    continue; "
		"    let x = 1; "
		"  } "
		"  return 0; "
		"}";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	ok = ok && strstr(err.message, "after continue") != NULL;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_unreachable_after_return(void) {
	const char *src =
		"fn main() int { "
		"  return 1; "
		"  let x = 2; "
		"}";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	ok = ok && strstr(err.message, "after return") != NULL;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_call_callee_boundary(void) {
	const char *src = "fn main() int { let x = 0; return (x = 1)(2); }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = !semantic_analyze(result.root, &err) && err.code == ERR_SEMANTIC;
	ok = ok && strstr(err.message, "callee must be an identifier") != NULL;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_chained_assignment_in_call_args(void) {
	const char *src =
		"fn sum(int a, int b) int { return a + b; } "
		"fn main() int { let x = 0; return sum((x = 1), (x = x + 1)); }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = semantic_analyze(result.root, &err);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_parser_assignment_expression(void) {
	const char *src =
		"fn main() int { "
		"  let i = 0; "
		"  let j = (i = i + 1); "
		"  return j; "
		"}";
	token_vec tokens;
	compile_error err;
	parse_result result;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	ok = semantic_analyze(result.root, &err);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_runtime_short_circuit_or(void) {
	const char *src =
		"fn main() int { "
		"  let x = 0; "
		"  if true || (1 / x > 0) { return 1; } "
		"  return 0; "
		"}";
	token_vec tokens;
	compile_error err;
	parse_result result;
	IR ir;
	FILE *tmp;
	char buf[4096];
	size_t n;
	long ret = 0;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	if (!semantic_analyze(result.root, &err)) {
		parser_parse_result_free(&result);
		return false;
	}

	ir_init(&ir);
	if (!ir_generate_from_ast(result.root, &ir, &err)) {
		ir_free(&ir);
		parser_parse_result_free(&result);
		return false;
	}

	tmp = tmpfile();
	if (!tmp) {
		ir_free(&ir);
		parser_parse_result_free(&result);
		return false;
	}

	generate_code(&ir, tmp);
	fflush(tmp);
	fseek(tmp, 0, SEEK_SET);
	n = fread(buf, 1, sizeof(buf) - 1, tmp);
	buf[n] = '\0';
	fclose(tmp);

	ok = runtime_execute_text(buf, "main", &ret, &err);
	ok = ok && ret == 1;

	ir_free(&ir);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_runtime_short_circuit_and_side_effect_order(void) {
	const char *src =
		"fn main() int { "
		"  let x = 0; "
		"  if false && ((x = 1) > 0) { return 2; } "
		"  return x; "
		"}";
	token_vec tokens;
	compile_error err;
	parse_result result;
	IR ir;
	FILE *tmp;
	char buf[4096];
	size_t n;
	long ret = 0;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	if (!semantic_analyze(result.root, &err)) {
		parser_parse_result_free(&result);
		return false;
	}

	ir_init(&ir);
	if (!ir_generate_from_ast(result.root, &ir, &err)) {
		ir_free(&ir);
		parser_parse_result_free(&result);
		return false;
	}

	tmp = tmpfile();
	if (!tmp) {
		ir_free(&ir);
		parser_parse_result_free(&result);
		return false;
	}

	generate_code(&ir, tmp);
	fflush(tmp);
	fseek(tmp, 0, SEEK_SET);
	n = fread(buf, 1, sizeof(buf) - 1, tmp);
	buf[n] = '\0';
	fclose(tmp);

	ok = runtime_execute_text(buf, "main", &ret, &err);
	ok = ok && ret == 0;

	ir_free(&ir);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_ir_generation_entry(void) {
	const char *src = "fn add(a, b) { let c = a + b; if (c > 0) { return c; } return a; }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	IR ir;
	int i;
	bool has_func_begin = false;
	bool has_add = false;
	bool has_ret = false;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	if (!semantic_analyze(result.root, &err)) {
		parser_parse_result_free(&result);
		return false;
	}

	ir_init(&ir);
	if (!ir_generate_from_ast(result.root, &ir, &err)) {
		ir_free(&ir);
		parser_parse_result_free(&result);
		return false;
	}

	for (i = 0; i < ir.instruction_count; i++) {
		if (ir.instructions[i].type == IR_FUNC_BEGIN) {
			has_func_begin = true;
		}
		if (ir.instructions[i].type == IR_ADD) {
			has_add = true;
		}
		if (ir.instructions[i].type == IR_RET) {
			has_ret = true;
		}
	}

	ir_free(&ir);
	parser_parse_result_free(&result);
	return has_func_begin && has_add && has_ret;
}

static bool test_codegen_end_to_end(void) {
	const char *src = "fn pick(a, b) { if (a < b) { return a; } return b; }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	IR ir;
	FILE *tmp;
	char buf[4096];
	size_t n;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	if (!semantic_analyze(result.root, &err)) {
		parser_parse_result_free(&result);
		return false;
	}

	ir_init(&ir);
	if (!ir_generate_from_ast(result.root, &ir, &err)) {
		ir_free(&ir);
		parser_parse_result_free(&result);
		return false;
	}

	tmp = tmpfile();
	if (!tmp) {
		ir_free(&ir);
		parser_parse_result_free(&result);
		return false;
	}

	generate_code(&ir, tmp);
	fflush(tmp);
	fseek(tmp, 0, SEEK_SET);
	n = fread(buf, 1, sizeof(buf) - 1, tmp);
	buf[n] = '\0';
	fclose(tmp);

	ok = strstr(buf, "FUNC_BEGIN") != NULL;
	ok = ok && strstr(buf, "SSEED-TARGET-V1") != NULL;
	ok = ok && strstr(buf, "FUNC_BEGIN|") != NULL;
	ok = ok && strstr(buf, "LABEL|") != NULL;
	ok = ok && strstr(buf, "JUMP_IF_FALSE|") != NULL;
	ok = ok && strstr(buf, "RET|") != NULL;
	ok = ok && strstr(buf, "|_|") != NULL;
	ok = ok && strstr(buf, "LABEL") != NULL;
	ok = ok && strstr(buf, "JUMP_IF_FALSE") != NULL;
	ok = ok && strstr(buf, "RET") != NULL;

	ir_free(&ir);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_runtime_minimal_loop(void) {
	const char *src = "fn main() { let x = 1 + 2; return x; }";
	token_vec tokens;
	compile_error err;
	parse_result result;
	IR ir;
	FILE *tmp;
	char buf[4096];
	size_t n;
	long ret = 0;
	bool ok;

	if (!lexer_scan(src, &tokens, &err)) {
		return false;
	}
	result = parser_parse_tokens(&tokens, &err);
	token_vec_free(&tokens);
	if (!result.root) {
		return false;
	}
	if (!semantic_analyze(result.root, &err)) {
		parser_parse_result_free(&result);
		return false;
	}

	ir_init(&ir);
	if (!ir_generate_from_ast(result.root, &ir, &err)) {
		ir_free(&ir);
		parser_parse_result_free(&result);
		return false;
	}

	tmp = tmpfile();
	if (!tmp) {
		ir_free(&ir);
		parser_parse_result_free(&result);
		return false;
	}

	generate_code(&ir, tmp);
	fflush(tmp);
	fseek(tmp, 0, SEEK_SET);
	n = fread(buf, 1, sizeof(buf) - 1, tmp);
	buf[n] = '\0';
	fclose(tmp);

	ok = runtime_execute_text(buf, "main", &ret, &err);
	ok = ok && ret == 3;

	ir_free(&ir);
	parser_parse_result_free(&result);
	return ok;
}

int main(void) {
	bool ok = true;

	ok = ok && test_let_statement();
	ok = ok && test_function_header();
	ok = ok && test_illegal_char_error();
	ok = ok && test_unterminated_string_error();
	ok = ok && test_parser_let_and_precedence();
	ok = ok && test_parser_return_and_block();
	ok = ok && test_parser_control_flow_and_function();
	ok = ok && test_semantic_ok();
	ok = ok && test_semantic_undeclared_symbol();
	ok = ok && test_semantic_return_outside_function();
	ok = ok && test_semantic_call_arity_mismatch();
	ok = ok && test_semantic_return_type_mismatch();
	ok = ok && test_semantic_call_arg_type_mismatch();
	ok = ok && test_semantic_missing_return_path();
	ok = ok && test_semantic_assignment_and_loop_control();
	ok = ok && test_semantic_bool_flow();
	ok = ok && test_semantic_unreachable_after_break();
	ok = ok && test_semantic_unreachable_after_continue();
	ok = ok && test_semantic_unreachable_after_return();
	ok = ok && test_semantic_call_callee_boundary();
	ok = ok && test_semantic_chained_assignment_in_call_args();
	ok = ok && test_parser_assignment_expression();
	ok = ok && test_ir_generation_entry();
	ok = ok && test_codegen_end_to_end();
	ok = ok && test_runtime_minimal_loop();
	ok = ok && test_runtime_short_circuit_or();
	ok = ok && test_runtime_short_circuit_and_side_effect_order();

	if (!ok) {
		fprintf(stderr, "seed parser/semantic/ir tests failed\n");
		return 1;
	}

	printf("seed parser/semantic/ir tests passed\n");
	return 0;
}