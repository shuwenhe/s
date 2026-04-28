#include "ast.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../error/error.h"

typedef struct parser {
	const token_vec *tokens;
	size_t current;
	struct compile_error *err;
} parser;

static char *dup_cstr(const char *s) {
	size_t n = strlen(s);
	char *out = (char *)malloc(n + 1);
	if (!out) {
		return NULL;
	}
	memcpy(out, s, n + 1);
	return out;
}

void ast_vec_init(ast_vec *vec) {
	vec->data = NULL;
	vec->len = 0;
	vec->cap = 0;
}

int ast_vec_push(ast_vec *vec, ast_node *node) {
	if (vec->len == vec->cap) {
		size_t next_cap = (vec->cap == 0) ? 8 : vec->cap * 2;
		ast_node **next_data = (ast_node **)realloc(vec->data, next_cap * sizeof(ast_node *));
		if (!next_data) {
			return 0;
		}
		vec->data = next_data;
		vec->cap = next_cap;
	}
	vec->data[vec->len++] = node;
	return 1;
}

void ast_vec_free(ast_vec *vec) {
	free(vec->data);
	vec->data = NULL;
	vec->len = 0;
	vec->cap = 0;
}

const char *ast_kind_name(ast_kind kind) {
	switch (kind) {
		case AST_PROGRAM: return "PROGRAM";
		case AST_BLOCK: return "BLOCK";
		case AST_LET_STMT: return "LET_STMT";
			case AST_ASSIGN_STMT: return "ASSIGN_STMT";
		case AST_RETURN_STMT: return "RETURN_STMT";
			case AST_BREAK_STMT: return "BREAK_STMT";
			case AST_CONTINUE_STMT: return "CONTINUE_STMT";
		case AST_EXPR_STMT: return "EXPR_STMT";
		case AST_PACKAGE_DECL: return "PACKAGE_DECL";
		case AST_USE_DECL: return "USE_DECL";
		case AST_IF_STMT: return "IF_STMT";
		case AST_WHILE_STMT: return "WHILE_STMT";
		case AST_FOR_STMT: return "FOR_STMT";
		case AST_FN_STMT: return "FN_STMT";
		case AST_BINARY_EXPR: return "BINARY_EXPR";
		case AST_ASSIGN_EXPR: return "ASSIGN_EXPR";
		case AST_UNARY_EXPR: return "UNARY_EXPR";
		case AST_IDENT_EXPR: return "IDENT_EXPR";
		case AST_NUMBER_EXPR: return "NUMBER_EXPR";
			case AST_BOOL_EXPR: return "BOOL_EXPR";
		case AST_STRING_EXPR: return "STRING_EXPR";
		case AST_CALL_EXPR: return "CALL_EXPR";
		default: return "UNKNOWN_AST";
	}
}

ast_node *ast_new(ast_kind kind, source_pos pos) {
	ast_node *node = (ast_node *)calloc(1, sizeof(ast_node));
	if (!node) {
		return NULL;
	}
	node->kind = kind;
	node->pos = pos;
	if (kind == AST_PROGRAM) {
		ast_vec_init(&node->as.program.statements);
	} else if (kind == AST_BLOCK) {
		ast_vec_init(&node->as.block.statements);
	} else if (kind == AST_CALL_EXPR) {
		ast_vec_init(&node->as.call_expr.args);
	}
	return node;
}

void ast_free(ast_node *node) {
	size_t i;
	if (!node) {
		return;
	}

	switch (node->kind) {
		case AST_PROGRAM:
			for (i = 0; i < node->as.program.statements.len; i++) {
				ast_free(node->as.program.statements.data[i]);
			}
			ast_vec_free(&node->as.program.statements);
			break;
		case AST_BLOCK:
			for (i = 0; i < node->as.block.statements.len; i++) {
				ast_free(node->as.block.statements.data[i]);
			}
			ast_vec_free(&node->as.block.statements);
			break;
		case AST_LET_STMT:
			free(node->as.let_stmt.name);
			ast_free(node->as.let_stmt.value);
			break;
			case AST_ASSIGN_STMT:
				free(node->as.assign_stmt.name);
				ast_free(node->as.assign_stmt.value);
				break;
		case AST_RETURN_STMT:
			ast_free(node->as.return_stmt.value);
			break;
			case AST_BREAK_STMT:
			case AST_CONTINUE_STMT:
				break;
		case AST_EXPR_STMT:
			ast_free(node->as.expr_stmt.expr);
			break;
		case AST_PACKAGE_DECL:
			free(node->as.package_decl.name);
			break;
		case AST_USE_DECL:
			free(node->as.use_decl.module_path);
			free(node->as.use_decl.alias);
			break;
		case AST_IF_STMT:
			ast_free(node->as.if_stmt.condition);
			ast_free(node->as.if_stmt.then_branch);
			ast_free(node->as.if_stmt.else_branch);
			break;
		case AST_WHILE_STMT:
			ast_free(node->as.while_stmt.condition);
			ast_free(node->as.while_stmt.body);
			break;
		case AST_FOR_STMT:
			ast_free(node->as.for_stmt.init);
			ast_free(node->as.for_stmt.condition);
			ast_free(node->as.for_stmt.post);
			ast_free(node->as.for_stmt.body);
			break;
		case AST_FN_STMT:
			free(node->as.fn_stmt.name);
			for (i = 0; i < node->as.fn_stmt.param_count; i++) {
				free(node->as.fn_stmt.params[i]);
				free(node->as.fn_stmt.param_types[i]);
			}
			free(node->as.fn_stmt.params);
			free(node->as.fn_stmt.param_types);
			free(node->as.fn_stmt.return_type);
			ast_free(node->as.fn_stmt.body);
			break;
		case AST_BINARY_EXPR:
			ast_free(node->as.binary_expr.left);
			ast_free(node->as.binary_expr.right);
			break;
		case AST_ASSIGN_EXPR:
			free(node->as.assign_expr.name);
			ast_free(node->as.assign_expr.value);
			break;
		case AST_UNARY_EXPR:
			ast_free(node->as.unary_expr.operand);
			break;
		case AST_IDENT_EXPR:
			free(node->as.ident_expr.name);
			break;
		case AST_NUMBER_EXPR:
			free(node->as.number_expr.literal);
			break;
			case AST_BOOL_EXPR:
				break;
		case AST_STRING_EXPR:
			free(node->as.string_expr.literal);
			break;
		case AST_CALL_EXPR:
			ast_free(node->as.call_expr.callee);
			for (i = 0; i < node->as.call_expr.args.len; i++) {
				ast_free(node->as.call_expr.args.data[i]);
			}
			ast_vec_free(&node->as.call_expr.args);
			break;
	}
	free(node);
}

static const token *peek(parser *p) {
	return &p->tokens->data[p->current];
}

static const token *peek_next(parser *p) {
	if (p->current + 1 >= p->tokens->len) {
		return &p->tokens->data[p->tokens->len - 1];
	}
	return &p->tokens->data[p->current + 1];
}

static const token *prev(parser *p) {
	return &p->tokens->data[p->current - 1];
}

static int is_at_end(parser *p) {
	return peek(p)->type == TOKEN_EOF;
}

static const token *advance_tok(parser *p) {
	if (!is_at_end(p)) {
		p->current++;
	}
	return prev(p);
}

static int check(parser *p, token_type t) {
	if (is_at_end(p)) {
		return t == TOKEN_EOF;
	}
	return peek(p)->type == t;
}

static int check_next(parser *p, token_type t) {
	if (is_at_end(p)) {
		return 0;
	}
	return peek_next(p)->type == t;
}

static int match(parser *p, token_type t) {
	if (!check(p, t)) {
		return 0;
	}
	advance_tok(p);
	return 1;
}

static void parse_error(parser *p, const token *tok, const char *fmt, ...) {
	char msg[256];
	va_list args;
	va_start(args, fmt);
	vsnprintf(msg, sizeof(msg), fmt, args);
	va_end(args);
	msg[sizeof(msg) - 1] = '\0';
	error_set(p->err, ERR_SYNTAX, tok->pos.line, tok->pos.column, "%s", msg);
}

static int expect(parser *p, token_type t, const char *what) {
	if (check(p, t)) {
		advance_tok(p);
		return 1;
	}
	parse_error(p, peek(p), "expected %s, got %s", what, token_type_name(peek(p)->type));
	return 0;
}

static int consume_optional_semicolon(parser *p) {
	if (match(p, TOKEN_SEMICOLON)) {
		return 1;
	}
	return 1;
}

static ast_node *parse_expression(parser *p);
static ast_node *parse_statement(parser *p);

static ast_node *parse_primary(parser *p) {
	const token *tok = peek(p);
	ast_node *node;

	if (match(p, TOKEN_NUMBER)) {
		node = ast_new(AST_NUMBER_EXPR, tok->pos);
		if (!node) return NULL;
		node->as.number_expr.literal = dup_cstr(tok->lexeme);
		if (!node->as.number_expr.literal) {
			ast_free(node);
			return NULL;
		}
		return node;
	}
	if (match(p, TOKEN_TRUE)) {
		node = ast_new(AST_BOOL_EXPR, tok->pos);
		if (!node) return NULL;
		node->as.bool_expr.value = 1;
		return node;
	}
	if (match(p, TOKEN_FALSE)) {
		node = ast_new(AST_BOOL_EXPR, tok->pos);
		if (!node) return NULL;
		node->as.bool_expr.value = 0;
		return node;
	}
	if (match(p, TOKEN_STRING)) {
		node = ast_new(AST_STRING_EXPR, tok->pos);
		if (!node) return NULL;
		node->as.string_expr.literal = dup_cstr(tok->lexeme);
		if (!node->as.string_expr.literal) {
			ast_free(node);
			return NULL;
		}
		return node;
	}
	if (match(p, TOKEN_IDENTIFIER)) {
		node = ast_new(AST_IDENT_EXPR, tok->pos);
		if (!node) return NULL;
		node->as.ident_expr.name = dup_cstr(tok->lexeme);
		if (!node->as.ident_expr.name) {
			ast_free(node);
			return NULL;
		}
		return node;
	}
	if (match(p, TOKEN_LPAREN)) {
		node = parse_expression(p);
		if (!node) {
			return NULL;
		}
		if (!expect(p, TOKEN_RPAREN, ")")) {
			ast_free(node);
			return NULL;
		}
		return node;
	}

	parse_error(p, tok, "expected expression, got %s", token_type_name(tok->type));
	return NULL;
}

static ast_node *parse_call(parser *p) {
	ast_node *expr = parse_primary(p);
	if (!expr) {
		return NULL;
	}

	while (match(p, TOKEN_LPAREN)) {
		ast_node *call = ast_new(AST_CALL_EXPR, prev(p)->pos);
		if (!call) {
			ast_free(expr);
			return NULL;
		}
		call->as.call_expr.callee = expr;
		if (!check(p, TOKEN_RPAREN)) {
			for (;;) {
				ast_node *arg = parse_expression(p);
				if (!arg) {
					ast_free(call);
					return NULL;
				}
				if (!ast_vec_push(&call->as.call_expr.args, arg)) {
					ast_free(arg);
					ast_free(call);
					return NULL;
				}
				if (!match(p, TOKEN_COMMA)) {
					break;
				}
			}
		}
		if (!expect(p, TOKEN_RPAREN, ")")) {
			ast_free(call);
			return NULL;
		}
		expr = call;
	}

	return expr;
}

static ast_node *parse_unary(parser *p) {
	const token *tok = peek(p);
	ast_node *node;
	ast_node *rhs;

	if (match(p, TOKEN_MINUS) || match(p, TOKEN_BANG)) {
		token_type unary_op = prev(p)->type;
		rhs = parse_unary(p);
		if (!rhs) {
			return NULL;
		}
		node = ast_new(AST_UNARY_EXPR, tok->pos);
		if (!node) {
			ast_free(rhs);
			return NULL;
		}
		node->as.unary_expr.op = unary_op;
		node->as.unary_expr.operand = rhs;
		return node;
	}

	return parse_call(p);
}

static ast_node *parse_factor(parser *p) {
	ast_node *expr = parse_unary(p);
	while (expr && (check(p, TOKEN_STAR) || check(p, TOKEN_SLASH))) {
		const token *op = advance_tok(p);
		ast_node *rhs = parse_unary(p);
		ast_node *parent;
		if (!rhs) {
			ast_free(expr);
			return NULL;
		}
		parent = ast_new(AST_BINARY_EXPR, op->pos);
		if (!parent) {
			ast_free(expr);
			ast_free(rhs);
			return NULL;
		}
		parent->as.binary_expr.op = op->type;
		parent->as.binary_expr.left = expr;
		parent->as.binary_expr.right = rhs;
		expr = parent;
	}
	return expr;
}

static ast_node *parse_term(parser *p) {
	ast_node *expr = parse_factor(p);
	while (expr && (check(p, TOKEN_PLUS) || check(p, TOKEN_MINUS))) {
		const token *op = advance_tok(p);
		ast_node *rhs = parse_factor(p);
		ast_node *parent;
		if (!rhs) {
			ast_free(expr);
			return NULL;
		}
		parent = ast_new(AST_BINARY_EXPR, op->pos);
		if (!parent) {
			ast_free(expr);
			ast_free(rhs);
			return NULL;
		}
		parent->as.binary_expr.op = op->type;
		parent->as.binary_expr.left = expr;
		parent->as.binary_expr.right = rhs;
		expr = parent;
	}
	return expr;
}

static ast_node *parse_comparison(parser *p) {
	ast_node *expr = parse_term(p);
	while (expr && (check(p, TOKEN_LT) || check(p, TOKEN_LE) || check(p, TOKEN_GT) || check(p, TOKEN_GE))) {
		const token *op = advance_tok(p);
		ast_node *rhs = parse_term(p);
		ast_node *parent;
		if (!rhs) {
			ast_free(expr);
			return NULL;
		}
		parent = ast_new(AST_BINARY_EXPR, op->pos);
		if (!parent) {
			ast_free(expr);
			ast_free(rhs);
			return NULL;
		}
		parent->as.binary_expr.op = op->type;
		parent->as.binary_expr.left = expr;
		parent->as.binary_expr.right = rhs;
		expr = parent;
	}
	return expr;
}

static ast_node *parse_equality(parser *p) {
	ast_node *expr = parse_comparison(p);
	while (expr && (check(p, TOKEN_EQ) || check(p, TOKEN_NE))) {
		const token *op = advance_tok(p);
		ast_node *rhs = parse_comparison(p);
		ast_node *parent;
		if (!rhs) {
			ast_free(expr);
			return NULL;
		}
		parent = ast_new(AST_BINARY_EXPR, op->pos);
		if (!parent) {
			ast_free(expr);
			ast_free(rhs);
			return NULL;
		}
		parent->as.binary_expr.op = op->type;
		parent->as.binary_expr.left = expr;
		parent->as.binary_expr.right = rhs;
		expr = parent;
	}
	return expr;
}

static ast_node *parse_logic_and(parser *p) {
	ast_node *expr = parse_equality(p);
	while (expr && check(p, TOKEN_AND_AND)) {
		const token *op = advance_tok(p);
		ast_node *rhs = parse_equality(p);
		ast_node *parent;
		if (!rhs) {
			ast_free(expr);
			return NULL;
		}
		parent = ast_new(AST_BINARY_EXPR, op->pos);
		if (!parent) {
			ast_free(expr);
			ast_free(rhs);
			return NULL;
		}
		parent->as.binary_expr.op = op->type;
		parent->as.binary_expr.left = expr;
		parent->as.binary_expr.right = rhs;
		expr = parent;
	}
	return expr;
}

static ast_node *parse_logic_or(parser *p) {
	ast_node *expr = parse_logic_and(p);
	while (expr && check(p, TOKEN_OR_OR)) {
		const token *op = advance_tok(p);
		ast_node *rhs = parse_logic_and(p);
		ast_node *parent;
		if (!rhs) {
			ast_free(expr);
			return NULL;
		}
		parent = ast_new(AST_BINARY_EXPR, op->pos);
		if (!parent) {
			ast_free(expr);
			ast_free(rhs);
			return NULL;
		}
		parent->as.binary_expr.op = op->type;
		parent->as.binary_expr.left = expr;
		parent->as.binary_expr.right = rhs;
		expr = parent;
	}
	return expr;
}

static ast_node *parse_assignment(parser *p) {
	ast_node *expr = parse_logic_or(p);
	ast_node *node;
	char *name;
	if (!expr) {
		return NULL;
	}
	if (!match(p, TOKEN_ASSIGN)) {
		return expr;
	}
	if (expr->kind != AST_IDENT_EXPR) {
		parse_error(p, prev(p), "invalid assignment target");
		ast_free(expr);
		return NULL;
	}
	name = dup_cstr(expr->as.ident_expr.name);
	if (!name) {
		ast_free(expr);
		error_set(p->err, ERR_OUT_OF_MEMORY, prev(p)->pos.line, prev(p)->pos.column, "out of memory");
		return NULL;
	}
	node = ast_new(AST_ASSIGN_EXPR, expr->pos);
	if (!node) {
		free(name);
		ast_free(expr);
		return NULL;
	}
	node->as.assign_expr.name = name;
	node->as.assign_expr.value = parse_assignment(p);
	ast_free(expr);
	if (!node->as.assign_expr.value) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_expression(parser *p) {
	return parse_assignment(p);
}

static ast_node *parse_block(parser *p) {
	ast_node *block = ast_new(AST_BLOCK, prev(p)->pos);
	if (!block) {
		return NULL;
	}

	while (!check(p, TOKEN_RBRACE) && !is_at_end(p)) {
		ast_node *stmt = parse_statement(p);
		if (!stmt) {
			ast_free(block);
			return NULL;
		}
		if (!ast_vec_push(&block->as.block.statements, stmt)) {
			ast_free(stmt);
			ast_free(block);
			return NULL;
		}
	}

	if (!expect(p, TOKEN_RBRACE, "}")) {
		ast_free(block);
		return NULL;
	}
	return block;
}

static ast_node *parse_let_statement(parser *p) {
	ast_node *node = ast_new(AST_LET_STMT, prev(p)->pos);
	const token *name_tok;
	if (!node) {
		return NULL;
	}
	if (!expect(p, TOKEN_IDENTIFIER, "identifier")) {
		ast_free(node);
		return NULL;
	}
	name_tok = prev(p);
	node->as.let_stmt.name = dup_cstr(name_tok->lexeme);
	if (!node->as.let_stmt.name) {
		ast_free(node);
		return NULL;
	}

	if (!expect(p, TOKEN_ASSIGN, "=")) {
		ast_free(node);
		return NULL;
	}

	node->as.let_stmt.value = parse_expression(p);
	if (!node->as.let_stmt.value) {
		ast_free(node);
		return NULL;
	}

	if (!consume_optional_semicolon(p)) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_return_statement(parser *p) {
	ast_node *node = ast_new(AST_RETURN_STMT, prev(p)->pos);
	if (!node) {
		return NULL;
	}

	if (!check(p, TOKEN_SEMICOLON) && !check(p, TOKEN_RBRACE)) {
		node->as.return_stmt.value = parse_expression(p);
		if (!node->as.return_stmt.value) {
			ast_free(node);
			return NULL;
		}
	}

	if (!consume_optional_semicolon(p)) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_break_statement(parser *p) {
	ast_node *node = ast_new(AST_BREAK_STMT, prev(p)->pos);
	if (!node) {
		return NULL;
	}
	if (!consume_optional_semicolon(p)) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_continue_statement(parser *p) {
	ast_node *node = ast_new(AST_CONTINUE_STMT, prev(p)->pos);
	if (!node) {
		return NULL;
	}
	if (!consume_optional_semicolon(p)) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_expr_statement(parser *p) {
	ast_node *node = ast_new(AST_EXPR_STMT, peek(p)->pos);
	if (!node) {
		return NULL;
	}

	node->as.expr_stmt.expr = parse_expression(p);
	if (!node->as.expr_stmt.expr) {
		ast_free(node);
		return NULL;
	}

	if (!consume_optional_semicolon(p)) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_for_init(parser *p) {
	ast_node *node;
	const token *name_tok;
	if (check(p, TOKEN_SEMICOLON)) {
		return NULL;
	}
	if (match(p, TOKEN_LET)) {
		node = ast_new(AST_LET_STMT, prev(p)->pos);
		if (!node) {
			return NULL;
		}
		if (!expect(p, TOKEN_IDENTIFIER, "identifier")) {
			ast_free(node);
			return NULL;
		}
		name_tok = prev(p);
		node->as.let_stmt.name = dup_cstr(name_tok->lexeme);
		if (!node->as.let_stmt.name) {
			error_set(p->err, ERR_OUT_OF_MEMORY, name_tok->pos.line, name_tok->pos.column, "out of memory");
			ast_free(node);
			return NULL;
		}
		if (!expect(p, TOKEN_ASSIGN, "=")) {
			ast_free(node);
			return NULL;
		}
		node->as.let_stmt.value = parse_expression(p);
		if (!node->as.let_stmt.value) {
			ast_free(node);
			return NULL;
		}
		return node;
	}

	node = ast_new(AST_EXPR_STMT, peek(p)->pos);
	if (!node) {
		return NULL;
	}
	node->as.expr_stmt.expr = parse_expression(p);
	if (!node->as.expr_stmt.expr) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_if_statement(parser *p) {
	ast_node *node = ast_new(AST_IF_STMT, prev(p)->pos);
	int has_paren;
	if (!node) {
		return NULL;
	}

	has_paren = match(p, TOKEN_LPAREN);
	node->as.if_stmt.condition = parse_expression(p);
	if (!node->as.if_stmt.condition) {
		ast_free(node);
		return NULL;
	}
	if (has_paren && !expect(p, TOKEN_RPAREN, ")")) {
		ast_free(node);
		return NULL;
	}
	node->as.if_stmt.then_branch = parse_statement(p);
	if (!node->as.if_stmt.then_branch) {
		ast_free(node);
		return NULL;
	}
	if (match(p, TOKEN_ELSE)) {
		node->as.if_stmt.else_branch = parse_statement(p);
		if (!node->as.if_stmt.else_branch) {
			ast_free(node);
			return NULL;
		}
	}

	return node;
}

static ast_node *parse_while_statement(parser *p) {
	ast_node *node = ast_new(AST_WHILE_STMT, prev(p)->pos);
	int has_paren;
	if (!node) {
		return NULL;
	}
	has_paren = match(p, TOKEN_LPAREN);
	node->as.while_stmt.condition = parse_expression(p);
	if (!node->as.while_stmt.condition) {
		ast_free(node);
		return NULL;
	}
	if (has_paren && !expect(p, TOKEN_RPAREN, ")")) {
		ast_free(node);
		return NULL;
	}
	node->as.while_stmt.body = parse_statement(p);
	if (!node->as.while_stmt.body) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_for_statement(parser *p) {
	ast_node *node = ast_new(AST_FOR_STMT, prev(p)->pos);
	if (!node) {
		return NULL;
	}
	if (!expect(p, TOKEN_LPAREN, "(")) {
		ast_free(node);
		return NULL;
	}

	node->as.for_stmt.init = parse_for_init(p);
	if (error_is_set(p->err)) {
		ast_free(node);
		return NULL;
	}
	if (!expect(p, TOKEN_SEMICOLON, ";")) {
		ast_free(node);
		return NULL;
	}

	if (!check(p, TOKEN_SEMICOLON)) {
		node->as.for_stmt.condition = parse_expression(p);
		if (!node->as.for_stmt.condition) {
			ast_free(node);
			return NULL;
		}
	}
	if (!expect(p, TOKEN_SEMICOLON, ";")) {
		ast_free(node);
		return NULL;
	}

	if (!check(p, TOKEN_RPAREN)) {
		node->as.for_stmt.post = parse_expression(p);
		if (!node->as.for_stmt.post) {
			ast_free(node);
			return NULL;
		}
	}
	if (!expect(p, TOKEN_RPAREN, ")")) {
		ast_free(node);
		return NULL;
	}

	node->as.for_stmt.body = parse_statement(p);
	if (!node->as.for_stmt.body) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static int parse_params(parser *p, ast_node *fn_node) {
	char **params = NULL;
	char **param_types = NULL;
	size_t count = 0;
	size_t cap = 0;

	if (check(p, TOKEN_RPAREN)) {
		fn_node->as.fn_stmt.params = NULL;
		fn_node->as.fn_stmt.param_types = NULL;
		fn_node->as.fn_stmt.param_count = 0;
		return 1;
	}

	for (;;) {
		const token *first_tok;
		const token *type_tok = NULL;
		const token *name_tok;
		char *name;
		char *type_name;
		if (!expect(p, TOKEN_IDENTIFIER, "parameter")) {
			goto fail;
		}
		first_tok = prev(p);
		name_tok = first_tok;

		if (check(p, TOKEN_IDENTIFIER) && (check_next(p, TOKEN_COMMA) || check_next(p, TOKEN_RPAREN))) {
			advance_tok(p);
			type_tok = first_tok;
			name_tok = prev(p);
		}

		name = dup_cstr(name_tok->lexeme);
		if (!name) {
			goto fail;
		}
		type_name = dup_cstr(type_tok ? type_tok->lexeme : "any");
		if (!type_name) {
			free(name);
			goto fail;
		}
		if (count == cap) {
			size_t next_cap = (cap == 0) ? 4 : cap * 2;
			char **next_params = (char **)malloc(next_cap * sizeof(char *));
			char **next_param_types = (char **)malloc(next_cap * sizeof(char *));
			if (!next_params) {
				free(name);
				free(type_name);
				goto fail;
			}
			if (!next_param_types) {
				free(next_params);
				free(name);
				free(type_name);
				goto fail;
			}
			if (count > 0) {
				memcpy(next_params, params, count * sizeof(char *));
				memcpy(next_param_types, param_types, count * sizeof(char *));
			}
			free(params);
			free(param_types);
			params = next_params;
			param_types = next_param_types;
			cap = next_cap;
		}
		params[count++] = name;
		param_types[count - 1] = type_name;
		if (!match(p, TOKEN_COMMA)) {
			break;
		}
	}

	fn_node->as.fn_stmt.params = params;
	fn_node->as.fn_stmt.param_types = param_types;
	fn_node->as.fn_stmt.param_count = count;
	return 1;

fail:
	if (!error_is_set(p->err)) {
		error_set(p->err, ERR_OUT_OF_MEMORY, peek(p)->pos.line, peek(p)->pos.column, "out of memory");
	}
	while (count > 0) {
		free(params[--count]);
		free(param_types[count]);
	}
	free(params);
	free(param_types);
	return 0;
}

static ast_node *parse_fn_statement(parser *p) {
	ast_node *node = ast_new(AST_FN_STMT, prev(p)->pos);
	const token *name_tok;
	if (!node) {
		return NULL;
	}

	if (!expect(p, TOKEN_IDENTIFIER, "function name")) {
		ast_free(node);
		return NULL;
	}
	name_tok = prev(p);
	node->as.fn_stmt.name = dup_cstr(name_tok->lexeme);
	if (!node->as.fn_stmt.name) {
		error_set(p->err, ERR_OUT_OF_MEMORY, name_tok->pos.line, name_tok->pos.column, "out of memory");
		ast_free(node);
		return NULL;
	}
	node->as.fn_stmt.return_type = dup_cstr("any");
	if (!node->as.fn_stmt.return_type) {
		error_set(p->err, ERR_OUT_OF_MEMORY, name_tok->pos.line, name_tok->pos.column, "out of memory");
		ast_free(node);
		return NULL;
	}

	if (!expect(p, TOKEN_LPAREN, "(")) {
		ast_free(node);
		return NULL;
	}
	if (!parse_params(p, node)) {
		ast_free(node);
		return NULL;
	}
	if (!expect(p, TOKEN_RPAREN, ")")) {
		ast_free(node);
		return NULL;
	}

	if (check(p, TOKEN_IDENTIFIER) && check_next(p, TOKEN_LBRACE)) {
		char *ret_type;
		advance_tok(p);
		ret_type = dup_cstr(prev(p)->lexeme);
		if (!ret_type) {
			error_set(p->err, ERR_OUT_OF_MEMORY, prev(p)->pos.line, prev(p)->pos.column, "out of memory");
			ast_free(node);
			return NULL;
		}
		free(node->as.fn_stmt.return_type);
		node->as.fn_stmt.return_type = ret_type;
	} else if (check(p, TOKEN_LPAREN)) {
		char *ret_type;
		advance_tok(p);
		if (!expect(p, TOKEN_RPAREN, ")")) {
			ast_free(node);
			return NULL;
		}
		ret_type = dup_cstr("()");
		if (!ret_type) {
			error_set(p->err, ERR_OUT_OF_MEMORY, prev(p)->pos.line, prev(p)->pos.column, "out of memory");
			ast_free(node);
			return NULL;
		}
		free(node->as.fn_stmt.return_type);
		node->as.fn_stmt.return_type = ret_type;
	}

	if (!expect(p, TOKEN_LBRACE, "{")) {
		ast_free(node);
		return NULL;
	}
	node->as.fn_stmt.body = parse_block(p);
	if (!node->as.fn_stmt.body) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_package_decl(parser *p) {
	ast_node *node = ast_new(AST_PACKAGE_DECL, prev(p)->pos);
	const token *name_tok;
	if (!node) {
		return NULL;
	}
	if (!expect(p, TOKEN_IDENTIFIER, "package name")) {
		ast_free(node);
		return NULL;
	}
	name_tok = prev(p);
	node->as.package_decl.name = dup_cstr(name_tok->lexeme);
	if (!node->as.package_decl.name) {
		ast_free(node);
		return NULL;
	}
	consume_optional_semicolon(p);
	return node;
}

static ast_node *parse_use_decl(parser *p) {
	ast_node *node = ast_new(AST_USE_DECL, prev(p)->pos);
	char path[256];
	char alias_buf[64];
	size_t path_len = 0;
	if (!node) {
		return NULL;
	}
	path[0] = '\0';
	alias_buf[0] = '\0';

	if (!expect(p, TOKEN_IDENTIFIER, "module path")) {
		ast_free(node);
		return NULL;
	}
	snprintf(path, sizeof(path), "%s", prev(p)->lexeme);
	snprintf(alias_buf, sizeof(alias_buf), "%s", prev(p)->lexeme);
	path_len = strlen(path);

	while (match(p, TOKEN_DOT)) {
		if (!expect(p, TOKEN_IDENTIFIER, "path segment")) {
			ast_free(node);
			return NULL;
		}
		if (path_len + 1 + strlen(prev(p)->lexeme) + 1 >= sizeof(path)) {
			error_set(p->err, ERR_SYNTAX, prev(p)->pos.line, prev(p)->pos.column, "module path too long");
			ast_free(node);
			return NULL;
		}
		strcat(path, ".");
		strcat(path, prev(p)->lexeme);
		snprintf(alias_buf, sizeof(alias_buf), "%s", prev(p)->lexeme);
		path_len = strlen(path);
	}

	node->as.use_decl.module_path = dup_cstr(path);
	if (!node->as.use_decl.module_path) {
		ast_free(node);
		return NULL;
	}

	if (match(p, TOKEN_AS)) {
		if (!expect(p, TOKEN_IDENTIFIER, "alias")) {
			ast_free(node);
			return NULL;
		}
		node->as.use_decl.alias = dup_cstr(prev(p)->lexeme);
		if (!node->as.use_decl.alias) {
			ast_free(node);
			return NULL;
		}
	} else {
		node->as.use_decl.alias = dup_cstr(alias_buf);
		if (!node->as.use_decl.alias) {
			ast_free(node);
			return NULL;
		}
	}

	consume_optional_semicolon(p);
	return node;
}

static ast_node *parse_statement(parser *p) {
	if (match(p, TOKEN_LET)) {
		return parse_let_statement(p);
	}
	if (match(p, TOKEN_RETURN)) {
		return parse_return_statement(p);
	}
	if (match(p, TOKEN_BREAK)) {
		return parse_break_statement(p);
	}
	if (match(p, TOKEN_CONTINUE)) {
		return parse_continue_statement(p);
	}
	if (match(p, TOKEN_IF)) {
		return parse_if_statement(p);
	}
	if (match(p, TOKEN_WHILE)) {
		return parse_while_statement(p);
	}
	if (match(p, TOKEN_FOR)) {
		return parse_for_statement(p);
	}
	if (match(p, TOKEN_FN)) {
		return parse_fn_statement(p);
	}
	if (match(p, TOKEN_LBRACE)) {
		return parse_block(p);
	}
	return parse_expr_statement(p);
}

static ast_node *parse_top_level(parser *p) {
	if (match(p, TOKEN_PACKAGE)) {
		return parse_package_decl(p);
	}
	if (match(p, TOKEN_USE)) {
		return parse_use_decl(p);
	}
	return parse_statement(p);
}

parse_result parser_parse_tokens(const token_vec *tokens, compile_error *err) {
	parser p;
	parse_result out;
	out.root = NULL;
	p.tokens = tokens;
	p.current = 0;
	p.err = err;
	error_clear(err);

	out.root = ast_new(AST_PROGRAM, tokens->len > 0 ? tokens->data[0].pos : (source_pos){1, 1});
	if (!out.root) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return out;
	}

	while (!is_at_end(&p)) {
		ast_node *stmt = parse_top_level(&p);
		if (!stmt) {
			if (!error_is_set(err)) {
				error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			}
			ast_free(out.root);
			out.root = NULL;
			return out;
		}
		if (!ast_vec_push(&out.root->as.program.statements, stmt)) {
			ast_free(stmt);
			ast_free(out.root);
			out.root = NULL;
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return out;
		}
	}

	return out;
}

void parser_parse_result_free(parse_result *res) {
	if (!res) {
		return;
	}
	ast_free(res->root);
	res->root = NULL;
}
