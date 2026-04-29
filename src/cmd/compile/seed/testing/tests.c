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
	const char *src = "var x = 42;";
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
	const char *src = "var x = @;";
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
	const char *src = "var s = \"abc";
	token_vec tokens;
	compile_error err;
	bool ok = lexer_scan(src, &tokens, &err);
	if (ok) {
		token_vec_free(&tokens);
		return false;
	}
	return err.code == ERR_UNTERMINATED_STRING;
}

static bool test_line_comment_lexing(void) {
	const char *src = "var x = 1; // comment\nlet y = 2;";
	token_vec tokens;
	compile_error err;
	bool ok = lexer_scan(src, &tokens, &err);
	if (!ok) {
		return false;
	}
	ok = tokens.len >= 11;
	ok = ok && tokens.data[0].type == TOKEN_LET;
	ok = ok && tokens.data[5].type == TOKEN_LET;
	token_vec_free(&tokens);
	return ok;
}

static bool test_array_literal_lexing(void) {
	const char *src = "var xs = [1.0, 2.0, 3.0];";
	token_type expected[] = {
		TOKEN_LET,
		TOKEN_IDENTIFIER,
		TOKEN_ASSIGN,
		TOKEN_LBRACKET,
		TOKEN_NUMBER,
		TOKEN_COMMA,
		TOKEN_NUMBER,
		TOKEN_COMMA,
		TOKEN_NUMBER,
		TOKEN_RBRACKET,
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

static bool test_block_comment_lexing_and_error(void) {
	const char *ok_src = "var x = 1; /* block\ncomment */ var y = 2;";
	const char *bad_src = "var x = 1; /* unterminated";
	token_vec tokens;
	compile_error err;
	bool ok = lexer_scan(ok_src, &tokens, &err);
	if (!ok) {
		return false;
	}
	ok = tokens.len >= 11;
	ok = ok && tokens.data[0].type == TOKEN_LET;
	ok = ok && tokens.data[5].type == TOKEN_LET;
	token_vec_free(&tokens);
	if (!ok) {
		return false;
	}

	ok = lexer_scan(bad_src, &tokens, &err);
	if (ok) {
		token_vec_free(&tokens);
		return false;
	}
	return err.code == ERR_SYNTAX;
}

static bool test_parser_let_and_precedence(void) {
	const char *src = "var x = 1 + 2 * 3;";
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
	const char *src = "{ var x = 1; return x; }";
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

static bool test_parser_array_literal(void) {
	const char *src = "var xs = [1.0, 2.0, 3.0];";
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
	ok = expr->kind == AST_ARRAY_EXPR;
	ok = ok && expr->as.array_expr.items.len == 3;

	parser_parse_result_free(&result);
	return ok;
}

static bool test_parser_dotted_package_decl(void) {
	const char *src = "package neurx.test_tensor; fn main() int { return 0; }";
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
	ok = ok && result.root->as.program.statements.len >= 1;
	if (ok) {
		ast_node *decl = result.root->as.program.statements.data[0];
		ok = decl->kind == AST_PACKAGE_DECL;
		ok = ok && strcmp(decl->as.package_decl.name, "neurx.test_tensor") == 0;
	}

	parser_parse_result_free(&result);
	return ok;
}

static bool test_parser_dotted_use_decl(void) {
	const char *src = "use neurx.tensor.ops as ops; fn main() int { return 0; }";
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
	ok = ok && result.root->as.program.statements.len >= 1;
	if (ok) {
		ast_node *decl = result.root->as.program.statements.data[0];
		ok = decl->kind == AST_USE_DECL;
		ok = ok && strcmp(decl->as.use_decl.module_path, "neurx.tensor.ops") == 0;
		ok = ok && strcmp(decl->as.use_decl.alias, "ops") == 0;
	}

	parser_parse_result_free(&result);
	return ok;
}

static bool test_parser_use_selector_list(void) {
	const char *src = "use neurx.tensor.{Tensor, new, add}; fn main() int { return 0; }";
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
	ok = ok && result.root->as.program.statements.len >= 1;
	if (ok) {
		ast_node *decl = result.root->as.program.statements.data[0];
		ok = decl->kind == AST_USE_DECL;
		ok = ok && strcmp(decl->as.use_decl.module_path, "neurx.tensor") == 0;
		ok = ok && strcmp(decl->as.use_decl.alias, "tensor") == 0;
	}

	parser_parse_result_free(&result);
	return ok;
}

static bool test_parser_member_access_expr(void) {
	const char *src = "fn main() int { var a = 1; println(a.data); return 0; }";
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
	ok = ok && result.root->as.program.statements.len == 1;
	if (ok) {
		ast_node *fn = result.root->as.program.statements.data[0];
		ast_node *stmt;
		ast_node *call;
		ast_node *arg;
		ok = fn->kind == AST_FN_STMT;
		ok = ok && fn->as.fn_stmt.body != NULL;
		ok = ok && fn->as.fn_stmt.body->kind == AST_BLOCK;
		ok = ok && fn->as.fn_stmt.body->as.block.statements.len >= 2;
		if (ok) {
			stmt = fn->as.fn_stmt.body->as.block.statements.data[1];
			ok = stmt->kind == AST_EXPR_STMT;
			if (ok) {
				call = stmt->as.expr_stmt.expr;
				ok = call->kind == AST_CALL_EXPR;
				ok = ok && call->as.call_expr.args.len == 1;
				if (ok) {
					arg = call->as.call_expr.args.data[0];
					ok = arg->kind == AST_MEMBER_EXPR;
					ok = ok && strcmp(arg->as.member_expr.member, "data") == 0;
				}
			}
		}
	}

	parser_parse_result_free(&result);
	return ok;
}

static bool test_parser_control_flow_and_function(void) {
	const char *src =
		"fn sum(a, b) { var i = 0; while (i < b) { i + 1; } return a + b; } "
		"for (var k = 0; k < 10; k + 1) { if (k == 3) { k + 1; } else { k + 2; } }";
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
	const char *src = "fn add(a, b) { var c = a + b; return c; }";
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
		"  var i = 0; "
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
		"    var x = 1; "
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
		"    var x = 1; "
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
		"  var x = 2; "
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

static bool test_semantic_nested_if_dead_code(void) {
	const char *src =
		"fn main() int { "
		"  if true { "
		"    if true { return 1; } else { return 2; } "
		"  } else { "
		"    return 3; "
		"  } "
		"  var x = 0; "
		"  return x; "
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

static bool test_semantic_short_circuit_assignment_propagation(void) {
	const char *src =
		"fn id(any x) any { return x; } "
		"fn need_int(int x) int { return x; } "
		"fn main() int { "
		"  var flag = false; "
		"  var b = id(0); "
		"  flag && (b = \"x\"); "
		"  return need_int(b); "
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

static bool test_semantic_builtin_signature_check(void) {
	const char *src = "fn main() int { len(); return 0; }";
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
	ok = ok && strstr(err.message, "at least 1") != NULL;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_import_signature_check(void) {
	const char *src =
		"use std.io.eprintln as say "
		"fn main() int { say(); return 0; }";
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
	ok = ok && strstr(err.message, "at least 1") != NULL;
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_path_sensitive_narrowing_if_and(void) {
	const char *src =
		"fn id(any x) any { return x; } "
		"fn takes_int(int x) int { return x; } "
		"fn takes_string(string s) int { return 1; } "
		"fn main() int { "
		"  var x = id(1); "
		"  var y = id(\"ok\"); "
		"  if x == 1 && y == \"ok\" { "
		"    return takes_int(x) + takes_string(y); "
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
	ok = semantic_analyze(result.root, &err);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_path_sensitive_narrowing_if_or_else(void) {
	const char *src =
		"fn id(any x) any { return x; } "
		"fn takes_int(int x) int { return x; } "
		"fn takes_string(string s) int { return 1; } "
		"fn main() int { "
		"  var x = id(2); "
		"  var y = id(\"s\"); "
		"  if x == 1 || y == \"ok\" { "
		"    return 0; "
		"  } else { "
		"    return takes_int(x) + takes_string(y); "
		"  } "
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

static bool test_semantic_metadata_import_signature_success(void) {
	const char *src =
		"use internal.buildcfg.goarch as goarch "
		"fn main() int { "
		"  var arch = goarch(); "
		"  if arch == \"amd64\" { return 1; } "
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
	ok = semantic_analyze(result.root, &err);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_semantic_call_callee_boundary(void) {
	const char *src = "fn main() int { var x = 0; return (x = 1)(2); }";
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
		"fn main() int { var x = 0; return sum((x = 1), (x = x + 1)); }";
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
		"  var i = 0; "
		"  var j = (i = i + 1); "
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
		"  var x = 0; "
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
		"  var x = 0; "
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

static bool test_runtime_function_call_and_tail_expr_return(void) {
	const char *src =
		"fn id(x) int { x } "
		"fn add(a, b) int { return a + b; } "
		"fn main() int { return add(id(2), 3); }";
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

	ok = strstr(buf, "ARG|") != NULL;
	ok = ok && strstr(buf, "CALL|") != NULL;
	ok = ok && runtime_execute_text(buf, "main", &ret, &err);
	ok = ok && ret == 5;

	ir_free(&ir);
	parser_parse_result_free(&result);
	return ok;
}

static bool test_runtime_string_value_semantics(void) {
	const char *target_text =
		"SSEED-TARGET-V1\n"
		"FUNC_BEGIN|main|_|_\n"
		"CMP_EQ|eq1|\"ab\"|\"ab\"\n"
		"JUMP_IF_FALSE|fail|eq1|_\n"
		"ADD|s|\"a\"|\"b\"\n"
		"CMP_EQ|eq2|s|\"ab\"\n"
		"JUMP_IF_FALSE|fail|eq2|_\n"
		"RET|7|_|_\n"
		"LABEL|fail|_|_\n"
		"RET|0|_|_\n"
		"FUNC_END|main|_|_\n";
	compile_error err;
	long ret = 0;
	bool ok = runtime_execute_text(target_text, "main", &ret, &err);
	return ok && ret == 7;
}

static bool test_runtime_string_mixed_compare_error(void) {
	const char *target_text =
		"SSEED-TARGET-V1\n"
		"FUNC_BEGIN|main|_|_\n"
		"CMP_EQ|bad|\"1\"|1\n"
		"RET|bad|_|_\n"
		"FUNC_END|main|_|_\n";
	compile_error err;
	long ret = 0;
	bool ok = runtime_execute_text(target_text, "main", &ret, &err);
	(void)ret;
	if (ok) {
		return false;
	}
	if (err.code != ERR_SEMANTIC) {
		return false;
	}
	return strstr(err.message, "operand types to match") != NULL;
}

static bool test_runtime_string_escape_sequences(void) {
	const char *target_text =
		"SSEED-TARGET-V1\n"
		"FUNC_BEGIN|main|_|_\n"
		"ADD|s1|\"\\n\"|\"\\t\"\n"
		"ADD|s2|\"\\\\\"|\"x\"\n"
		"ADD|s|s1|s2\n"
		"RET|s|_|_\n"
		"FUNC_END|main|_|_\n";
	compile_error err;
	long ret = 0;
	bool ok = runtime_execute_text(target_text, "main", &ret, &err);
	return ok && ret == 4;
}

static bool test_runtime_string_long_boundary(void) {
	char lit[304];
	char target_text[768];
	compile_error err;
	long ret = 0;
	size_t i;
	bool ok;

	lit[0] = '"';
	for (i = 1; i <= 300; i++) {
		lit[i] = 'a';
	}
	lit[301] = '"';
	lit[302] = '\0';

	if (snprintf(
			target_text,
			sizeof(target_text),
			"SSEED-TARGET-V1\n"
			"FUNC_BEGIN|main|_|_\n"
			"RET|%s|_|_\n"
			"FUNC_END|main|_|_\n",
			lit
		) < 0) {
		return false;
	}

	ok = runtime_execute_text(target_text, "main", &ret, &err);
	return ok && ret == 300;
}

static bool test_ir_generation_entry(void) {
	const char *src = "fn add(a, b) { var c = a + b; if (c > 0) { return c; } return a; }";
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
	const char *src = "fn main() { var x = 1 + 2; return x; }";
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
	ok = ok && test_line_comment_lexing();
	ok = ok && test_array_literal_lexing();
	ok = ok && test_block_comment_lexing_and_error();
	ok = ok && test_parser_let_and_precedence();
	ok = ok && test_parser_return_and_block();
	ok = ok && test_parser_array_literal();
	ok = ok && test_parser_dotted_package_decl();
	ok = ok && test_parser_dotted_use_decl();
	ok = ok && test_parser_use_selector_list();
	ok = ok && test_parser_member_access_expr();
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
	ok = ok && test_semantic_nested_if_dead_code();
	ok = ok && test_semantic_call_callee_boundary();
	ok = ok && test_semantic_chained_assignment_in_call_args();
	ok = ok && test_semantic_short_circuit_assignment_propagation();
	ok = ok && test_semantic_builtin_signature_check();
	ok = ok && test_semantic_import_signature_check();
	ok = ok && test_semantic_path_sensitive_narrowing_if_and();
	ok = ok && test_semantic_path_sensitive_narrowing_if_or_else();
	ok = ok && test_semantic_metadata_import_signature_success();
	ok = ok && test_parser_assignment_expression();
	ok = ok && test_ir_generation_entry();
	ok = ok && test_codegen_end_to_end();
	ok = ok && test_runtime_minimal_loop();
	ok = ok && test_runtime_short_circuit_or();
	ok = ok && test_runtime_short_circuit_and_side_effect_order();
	ok = ok && test_runtime_function_call_and_tail_expr_return();
	ok = ok && test_runtime_string_value_semantics();
	ok = ok && test_runtime_string_mixed_compare_error();
	ok = ok && test_runtime_string_escape_sequences();
	ok = ok && test_runtime_string_long_boundary();

	if (!ok) {
		fprintf(stderr, "seed parser/semantic/ir tests failed\n");
		return 1;
	}

	printf("seed parser/semantic/ir tests passed\n");
	return 0;
}