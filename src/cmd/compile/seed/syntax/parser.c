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
		case AST_ARRAY_EXPR: return "ARRAY_EXPR";
		case AST_MEMBER_EXPR: return "MEMBER_EXPR";
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
	} else if (kind == AST_ARRAY_EXPR) {
		ast_vec_init(&node->as.array_expr.items);
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
			for (i = 0; i < node->as.use_decl.selector_count; i++) {
				free(node->as.use_decl.selectors[i]);
			}
			free(node->as.use_decl.selectors);
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
		case AST_ARRAY_EXPR:
			for (i = 0; i < node->as.array_expr.items.len; i++) {
				ast_free(node->as.array_expr.items.data[i]);
			}
			ast_vec_free(&node->as.array_expr.items);
			break;
		case AST_MEMBER_EXPR:
			ast_free(node->as.member_expr.object);
			free(node->as.member_expr.member);
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
static int skip_brace_initializer(parser *p);
static int parse_dotted_path(parser *p,
	char *path,
	size_t path_size,
	char *alias_buf,
	size_t alias_size,
	const char *what,
	int allow_selector_suffix);

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
	if (match(p, TOKEN_LBRACKET)) {
		node = ast_new(AST_ARRAY_EXPR, tok->pos);
		if (!node) {
			return NULL;
		}
		if (!check(p, TOKEN_RBRACKET)) {
			for (;;) {
				ast_node *item = parse_expression(p);
				if (!item) {
					ast_free(node);
					return NULL;
				}
				if (!ast_vec_push(&node->as.array_expr.items, item)) {
					ast_free(item);
					ast_free(node);
					return NULL;
				}
				if (!match(p, TOKEN_COMMA)) {
					break;
				}
				if (check(p, TOKEN_RBRACKET)) {
					break;
				}
			}
		}
		if (!expect(p, TOKEN_RBRACKET, "]")) {
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
		if (!skip_brace_initializer(p)) {
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

	for (;;) {
		if (match(p, TOKEN_LPAREN)) {
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
			continue;
		}

		if (match(p, TOKEN_DOT)) {
			ast_node *member = ast_new(AST_MEMBER_EXPR, prev(p)->pos);
			if (!member) {
				ast_free(expr);
				return NULL;
			}
			if (!expect(p, TOKEN_IDENTIFIER, "member name")) {
				ast_free(member);
				ast_free(expr);
				return NULL;
			}
			member->as.member_expr.object = expr;
			member->as.member_expr.member = dup_cstr(prev(p)->lexeme);
			if (!member->as.member_expr.member) {
				ast_free(member);
				return NULL;
			}
			expr = member;
			continue;
		}

		break;
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

static ast_node *parse_fn_statement(parser *p) {
	ast_node *node = ast_new(AST_FN_STMT, prev(p)->pos);
	size_t cap = 0;
	char *ret_type;
	if (!node) {
		return NULL;
	}
	if (!expect(p, TOKEN_IDENTIFIER, "function name")) {
		ast_free(node);
		return NULL;
	}
	node->as.fn_stmt.name = dup_cstr(prev(p)->lexeme);
	if (!node->as.fn_stmt.name) {
		ast_free(node);
		return NULL;
	}
	if (!expect(p, TOKEN_LPAREN, "(")) {
		ast_free(node);
		return NULL;
	}
	while (!check(p, TOKEN_RPAREN)) {
		char *param_name;
		char *param_type;
		if (!expect(p, TOKEN_IDENTIFIER, "parameter")) {
			ast_free(node);
			return NULL;
		}
		param_name = dup_cstr(prev(p)->lexeme);
		if (!param_name) {
			ast_free(node);
			return NULL;
		}
		param_type = dup_cstr("any");
		if (!param_type) {
			free(param_name);
			ast_free(node);
			return NULL;
		}
		if (check(p, TOKEN_IDENTIFIER) && !check_next(p, TOKEN_COMMA) && !check_next(p, TOKEN_RPAREN)) {
			advance_tok(p);
			free(param_type);
			param_type = dup_cstr(prev(p)->lexeme);
			if (!param_type) {
				free(param_name);
				ast_free(node);
				return NULL;
			}
		}
		if (node->as.fn_stmt.param_count == cap) {
			size_t next_cap = (cap == 0) ? 4 : cap * 2;
			char **next_params = (char **)realloc(node->as.fn_stmt.params, next_cap * sizeof(char *));
			char **next_types = (char **)realloc(node->as.fn_stmt.param_types, next_cap * sizeof(char *));
			if (!next_params || !next_types) {
				free(next_params);
				free(next_types);
				free(param_name);
				free(param_type);
				ast_free(node);
				return NULL;
			}
			node->as.fn_stmt.params = next_params;
			node->as.fn_stmt.param_types = next_types;
			cap = next_cap;
		}
		node->as.fn_stmt.params[node->as.fn_stmt.param_count] = param_name;
		node->as.fn_stmt.param_types[node->as.fn_stmt.param_count] = param_type;
		node->as.fn_stmt.param_count++;
		if (!match(p, TOKEN_COMMA)) {
			break;
		}
	}
	if (!expect(p, TOKEN_RPAREN, ")")) {
		ast_free(node);
		return NULL;
	}

	if (check(p, TOKEN_IDENTIFIER) && check_next(p, TOKEN_LBRACE)) {
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
	char package_path[256];
	char alias_buf[64];
	if (!node) {
		return NULL;
	}
	if (!parse_dotted_path(p, package_path, sizeof(package_path), alias_buf, sizeof(alias_buf), "package name", 0)) {
		ast_free(node);
		return NULL;
	}
	node->as.package_decl.name = dup_cstr(package_path);
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
	char *selectors_local[64];
	size_t selector_count = 0;
	size_t i;
	if (!node) {
		return NULL;
	}
	path[0] = '\0';
	alias_buf[0] = '\0';
	for (i = 0; i < 64; i++) {
		selectors_local[i] = NULL;
	}

	if (!parse_dotted_path(p, path, sizeof(path), alias_buf, sizeof(alias_buf), "module path", 1)) {
		ast_free(node);
		return NULL;
	}

	if (match(p, TOKEN_DOT)) {
		if (!expect(p, TOKEN_LBRACE, "{")) {
			ast_free(node);
			return NULL;
		}
		if (!expect(p, TOKEN_IDENTIFIER, "import symbol")) {
			ast_free(node);
			return NULL;
		}
		selectors_local[selector_count] = dup_cstr(prev(p)->lexeme);
		if (!selectors_local[selector_count]) {
			ast_free(node);
			return NULL;
		}
		selector_count++;
		while (match(p, TOKEN_COMMA)) {
			if (check(p, TOKEN_RBRACE)) {
				break;
			}
			if (!expect(p, TOKEN_IDENTIFIER, "import symbol")) {
				for (i = 0; i < selector_count; i++) {
					free(selectors_local[i]);
				}
				ast_free(node);
				return NULL;
			}
			if (selector_count >= 64) {
				error_set(p->err, ERR_SYNTAX, prev(p)->pos.line, prev(p)->pos.column, "too many import symbols");
				for (i = 0; i < selector_count; i++) {
					free(selectors_local[i]);
				}
				ast_free(node);
				return NULL;
			}
			selectors_local[selector_count] = dup_cstr(prev(p)->lexeme);
			if (!selectors_local[selector_count]) {
				for (i = 0; i < selector_count; i++) {
					free(selectors_local[i]);
				}
				ast_free(node);
				return NULL;
			}
			selector_count++;
		}
		if (!expect(p, TOKEN_RBRACE, "}")) {
			for (i = 0; i < selector_count; i++) {
				free(selectors_local[i]);
			}
			ast_free(node);
			return NULL;
		}
	}

	node->as.use_decl.module_path = dup_cstr(path);
	if (!node->as.use_decl.module_path) {
		for (i = 0; i < selector_count; i++) {
			free(selectors_local[i]);
		}
		ast_free(node);
		return NULL;
	}

	if (match(p, TOKEN_AS)) {
		if (!expect(p, TOKEN_IDENTIFIER, "alias")) {
			for (i = 0; i < selector_count; i++) {
				free(selectors_local[i]);
			}
			ast_free(node);
			return NULL;
		}
		node->as.use_decl.alias = dup_cstr(prev(p)->lexeme);
		if (!node->as.use_decl.alias) {
			for (i = 0; i < selector_count; i++) {
				free(selectors_local[i]);
			}
			ast_free(node);
			return NULL;
		}
	} else {
		node->as.use_decl.alias = dup_cstr(alias_buf);
		if (!node->as.use_decl.alias) {
			for (i = 0; i < selector_count; i++) {
				free(selectors_local[i]);
			}
			ast_free(node);
			return NULL;
		}
	}

	node->as.use_decl.selector_count = selector_count;
	if (selector_count > 0) {
		node->as.use_decl.selectors = (char **)calloc(selector_count, sizeof(char *));
		if (!node->as.use_decl.selectors) {
			for (i = 0; i < selector_count; i++) {
				free(selectors_local[i]);
			}
			ast_free(node);
			return NULL;
		}
		for (i = 0; i < selector_count; i++) {
			node->as.use_decl.selectors[i] = selectors_local[i];
		}
	} else {
		node->as.use_decl.selectors = NULL;
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
	if (check(p, TOKEN_IDENTIFIER)) {
		const token *tok = peek(p);
		if (strcmp(tok->lexeme, "struct") == 0 ||
			strcmp(tok->lexeme, "enum") == 0 ||
			strcmp(tok->lexeme, "trait") == 0 ||
			strcmp(tok->lexeme, "impl") == 0 ||
			strcmp(tok->lexeme, "const") == 0) {
			parse_error(p, tok, "unsupported top-level declaration '%s' in seed compiler", tok->lexeme);
			return NULL;
		}
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

static int skip_brace_initializer(parser *p) {
    if (match(p, TOKEN_LBRACE)) {
        while (!match(p, TOKEN_RBRACE)) {
            if (is_at_end(p)) {
                error_set(p->err, ERR_SYNTAX, peek(p)->pos.line, peek(p)->pos.column, "Unterminated brace initializer");
                return 0;
            }
            advance_tok(p);
        }
        return 1;
    }
    return 0;
}

static int parse_dotted_path(parser *p,
                             char *path,
                             size_t path_size,
                             char *alias_buf,
                             size_t alias_size,
                             const char *what,
                             int allow_selector_suffix) {
    size_t len = 0;
    if (!match(p, TOKEN_IDENTIFIER)) {
        error_set(p->err, ERR_SYNTAX, peek(p)->pos.line, peek(p)->pos.column, "Expected %s", what);
        return 0;
    }
    len += snprintf(path + len, path_size - len, "%s", prev(p)->lexeme);

    while (match(p, TOKEN_DOT)) {
        if (!match(p, TOKEN_IDENTIFIER)) {
            error_set(p->err, ERR_SYNTAX, peek(p)->pos.line, peek(p)->pos.column, "Expected identifier after '.' in %s", what);
            return 0;
        }
        len += snprintf(path + len, path_size - len, ".%s", prev(p)->lexeme);
    }

    if (allow_selector_suffix && match(p, TOKEN_AS)) {
        if (!match(p, TOKEN_IDENTIFIER)) {
            error_set(p->err, ERR_SYNTAX, peek(p)->pos.line, peek(p)->pos.column, "Expected alias after 'as'");
            return 0;
        }
        snprintf(alias_buf, alias_size, "%s", prev(p)->lexeme);
    }

    return 1;
}

// Load the module and add symbols to the scope
	bool load_module_and_add_to_scope(const char *module_path, char **selectors, size_t selector_count, compile_error *err);
