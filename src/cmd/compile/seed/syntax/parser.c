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

static ast_node *parse_extern_decl(parser *p);
static ast_node *parse_binding_statement(parser *p, int is_mutable);
static int looks_like_typed_binding(parser *p);
static int try_parse_typed_name(parser *p, token_type terminator, char **out_type, char **out_name);
static int try_parse_type_annotation(parser *p, char **out_type);
static char *join_lexemes_range(const token_vec *tokens, size_t start, size_t end);
static ast_node *parse_map_literal_expr(parser *p, const token *type_tok, const char *type_name);

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
		case AST_STRUCT_EXPR: return "STRUCT_EXPR";
		case AST_MEMBER_EXPR: return "MEMBER_EXPR";
		case AST_INDEX_EXPR: return "INDEX_EXPR";
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
		case AST_STRUCT_EXPR:
			free(node->as.struct_expr.type_name);
			if (node->as.struct_expr.field_names) {
				for (i = 0; i < node->as.struct_expr.field_count; i++) {
					free(node->as.struct_expr.field_names[i]);
				}
				free(node->as.struct_expr.field_names);
			}
			for (i = 0; i < node->as.struct_expr.field_values.len; i++) {
				ast_free(node->as.struct_expr.field_values.data[i]);
			}
			ast_vec_free(&node->as.struct_expr.field_values);
			break;
		case AST_MEMBER_EXPR:
			ast_free(node->as.member_expr.object);
			free(node->as.member_expr.member);
			break;
		case AST_INDEX_EXPR:
			ast_free(node->as.index_expr.object);
			ast_free(node->as.index_expr.index);
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
static ast_node *parse_assignment(parser *p);
static ast_node *parse_statement(parser *p);
static ast_node *parse_struct_decl(parser *p);
static int skip_brace_initializer(parser *p);
static ast_node *parse_struct_literal_expr(parser *p, const token *type_tok);
static int looks_like_struct_literal(parser *p);
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
	if (match(p, TOKEN_IF)) {
		ast_node *cond = parse_expression(p);
		ast_node *then_expr;
		ast_node *else_expr = NULL;
		if (!cond) {
			return NULL;
		}
		if (!expect(p, TOKEN_LBRACE, "{")) {
			ast_free(cond);
			return NULL;
		}
		then_expr = parse_expression(p);
		if (!then_expr) {
			ast_free(cond);
			return NULL;
		}
		if (!expect(p, TOKEN_RBRACE, "}")) {
			ast_free(cond);
			ast_free(then_expr);
			return NULL;
		}
		if (match(p, TOKEN_ELSE)) {
			if (!expect(p, TOKEN_LBRACE, "{")) {
				ast_free(cond);
				ast_free(then_expr);
				return NULL;
			}
			else_expr = parse_expression(p);
			if (!else_expr) {
				ast_free(cond);
				ast_free(then_expr);
				return NULL;
			}
			if (!expect(p, TOKEN_RBRACE, "}")) {
				ast_free(cond);
				ast_free(then_expr);
				ast_free(else_expr);
				return NULL;
			}
		}
		ast_free(cond);
		if (else_expr) {
			ast_free(else_expr);
		}
		return then_expr;
	}
	if (match(p, TOKEN_LBRACKET)) {
		node = ast_new(AST_ARRAY_EXPR, tok->pos);
		if (!node) {
			return NULL;
		}
		
		// After consuming [, check if this is []TYPE{ or [N]TYPE{ pattern
		size_t peek_pos = p->current;
		int is_typed = 0;
		
		// Look ahead for []TYPE{ pattern
		if (check(p, TOKEN_RBRACKET)) {
			// Might be []TYPE{...}
			advance_tok(p);  // move past ]
			if (check(p, TOKEN_IDENTIFIER)) {
				advance_tok(p);  // move past type name
				if (check(p, TOKEN_LBRACE)) {
					is_typed = 1;
				}
			}
		} else {
			// Might be [N]TYPE{...}
			// Find the closing ]
			int depth = 1;
			while (depth > 0 && !is_at_end(p)) {
				if (check(p, TOKEN_LBRACKET)) depth++;
				else if (check(p, TOKEN_RBRACKET)) depth--;
				if (depth > 0) advance_tok(p);
			}
			
			// Check if we found it and if it's followed by TYPE{
			if (check(p, TOKEN_RBRACKET)) {
				advance_tok(p);  // consume ]
				if (check(p, TOKEN_IDENTIFIER)) {
					advance_tok(p);  // consume type
					if (check(p, TOKEN_LBRACE)) {
						is_typed = 1;
					}
				}
			}
		}
		
		if (is_typed) {
			// We're now at the { token
			// Consume it
			if (!match(p, TOKEN_LBRACE)) {
				ast_free(node);
				return NULL;
			}

			/* Compatibility: accept capacity-only initializers like []float{cap: n}. */
			if (check(p, TOKEN_IDENTIFIER) && strcmp(peek(p)->lexeme, "cap") == 0) {
				advance_tok(p);
				if (!expect(p, TOKEN_COLON, ":")) {
					ast_free(node);
					return NULL;
				}
				if (!parse_assignment(p)) {
					ast_free(node);
					return NULL;
				}
				if (match(p, TOKEN_COMMA)) {
					/* allow trailing comma after cap initializer */
				}
			}

			// Parse array elements using parse_assignment to avoid comma operator issues
			if (!check(p, TOKEN_RBRACE)) {
				for (;;) {
					ast_node *item = parse_assignment(p);
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
					// Allow trailing comma
					if (check(p, TOKEN_RBRACE)) {
						break;
					}
				}
			}
			
			if (!expect(p, TOKEN_RBRACE, "}")) {
				ast_free(node);
				return NULL;
			}
			return node;
		}
		
		// Not a typed array, restore position and parse as [ ... ] literal
		p->current = peek_pos;
		
		if (!check(p, TOKEN_RBRACKET)) {
			for (;;) {
				ast_node *item = parse_assignment(p);
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
				if (check(p, TOKEN_RBRACE)) {
					break;
				}
			}
		}
		if (!expect(p, TOKEN_RBRACKET, "]")) {
			ast_free(node);
			return NULL;
		}
		/* Compatibility: accept typed literal prefix like []float{cap: n}. */
		if (match(p, TOKEN_IDENTIFIER)) {
			if (!skip_brace_initializer(p)) {
				ast_free(node);
				return NULL;
			}
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
		if (strcmp(tok->lexeme, "map") == 0 && check(p, TOKEN_LBRACKET)) {
			size_t saved = p->current;
			char *map_type = NULL;
			ast_node *map_expr = NULL;
			if (try_parse_type_annotation(p, &map_type) && check(p, TOKEN_LBRACE)) {
				map_expr = parse_map_literal_expr(p, tok, map_type);
				free(map_type);
				ast_free(node);
				return map_expr;
			}
			free(map_type);
			p->current = saved;
		}
		if (check(p, TOKEN_LBRACE) && looks_like_struct_literal(p)) {
			ast_node *struct_expr = parse_struct_literal_expr(p, tok);
			ast_free(node);
			return struct_expr;
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
		const token *next_tok = peek(p);
		const token *last_tok = prev(p);
		if (next_tok && last_tok && next_tok->pos.line > last_tok->pos.line) {
			break;
		}

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

		if (match(p, TOKEN_LBRACKET)) {
			ast_node *indexed;
			ast_node *index_expr = NULL;
			if (!check(p, TOKEN_RBRACKET)) {
				index_expr = parse_expression(p);
				if (!index_expr) {
					ast_free(expr);
					return NULL;
				}
			}
			if (!expect(p, TOKEN_RBRACKET, "]")) {
				ast_free(index_expr);
				ast_free(expr);
				return NULL;
			}
			indexed = ast_new(AST_INDEX_EXPR, prev(p)->pos);
			if (!indexed) {
				ast_free(index_expr);
				ast_free(expr);
				return NULL;
			}
			indexed->as.index_expr.object = expr;
			indexed->as.index_expr.index = index_expr;
			expr = indexed;
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

	{
		ast_node *expr = parse_call(p);
		if (!expr) {
			return NULL;
		}
		while (match(p, TOKEN_AS)) {
			if (!expect(p, TOKEN_IDENTIFIER, "cast type")) {
				ast_free(expr);
				return NULL;
			}
		}
		return expr;
	}
}

static ast_node *parse_factor(parser *p) {
	ast_node *expr = parse_unary(p);
	while (expr && (check(p, TOKEN_STAR) || check(p, TOKEN_SLASH) || check(p, TOKEN_PERCENT))) {
		size_t saved = p->current;
		advance_tok(p);
		if (match(p, TOKEN_ASSIGN)) {
			p->current = saved;
			break;
		}
		p->current = saved;
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
		size_t saved = p->current;
		advance_tok(p);
		if (match(p, TOKEN_ASSIGN)) {
			p->current = saved;
			break;
		}
		p->current = saved;
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
	if (check(p, TOKEN_PLUS) || check(p, TOKEN_MINUS) || check(p, TOKEN_STAR) || check(p, TOKEN_SLASH) || check(p, TOKEN_PERCENT)) {
		size_t saved = p->current;
		advance_tok(p);
		if (match(p, TOKEN_ASSIGN)) {
			/* Compatibility mode: consume compound assignment and keep RHS expression. */
			ast_node *rhs = parse_assignment(p);
			ast_free(expr);
			return rhs;
		}
		p->current = saved;
	}

	if (!match(p, TOKEN_ASSIGN)) {
		return expr;
	}
	if (expr->kind != AST_IDENT_EXPR) {
		/* Compatibility mode: allow non-identifier assignment targets by parsing RHS and dropping target. */
		{
			ast_node *rhs = parse_assignment(p);
			ast_free(expr);
			return rhs;
		}
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

static ast_node *parse_binding_statement(parser *p, int is_mutable) {
	ast_node *node = ast_new(AST_LET_STMT, prev(p)->pos);
	const token *name_tok;
	char *annotation = NULL;
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
	node->as.let_stmt.mutable = is_mutable ? 1 : 0;

	if (match(p, TOKEN_COLON)) {
		if (!try_parse_type_annotation(p, &annotation)) {
			ast_free(node);
			return NULL;
		}
	} else if (!check(p, TOKEN_ASSIGN)) {
		if (!try_parse_type_annotation(p, &annotation)) {
			ast_free(node);
			return NULL;
		}
	}
	free(annotation);

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

static ast_node *parse_typed_binding_statement(parser *p, int is_mutable) {
	ast_node *node;
	char *binding_type = NULL;
	char *binding_name = NULL;

	if (!try_parse_typed_name(p, TOKEN_ASSIGN, &binding_type, &binding_name)) {
		return NULL;
	}
	if (!expect(p, TOKEN_ASSIGN, "=")) {
		free(binding_type);
		free(binding_name);
		return NULL;
	}

	node = ast_new(AST_LET_STMT, prev(p)->pos);
	if (!node) {
		free(binding_type);
		free(binding_name);
		return NULL;
	}
	node->as.let_stmt.mutable = is_mutable ? 1 : 0;
	node->as.let_stmt.name = dup_cstr(binding_name);
	if (!node->as.let_stmt.name) {
		free(binding_type);
		free(binding_name);
		ast_free(node);
		return NULL;
	}
	node->as.let_stmt.value = parse_expression(p);
	if (!node->as.let_stmt.value) {
		free(binding_type);
		free(binding_name);
		ast_free(node);
		return NULL;
	}
	if (!consume_optional_semicolon(p)) {
		free(binding_type);
		free(binding_name);
		ast_free(node);
		return NULL;
	}

	free(binding_type);
	free(binding_name);
	return node;
}

static int looks_like_typed_binding(parser *p) {
	size_t saved = p->current;
	char *parsed_type = NULL;
	char *parsed_name = NULL;
	int ok = 0;

	if (try_parse_typed_name(p, TOKEN_ASSIGN, &parsed_type, &parsed_name) && check(p, TOKEN_ASSIGN)) {
		ok = 1;
	}
	free(parsed_type);
	free(parsed_name);
	p->current = saved;
	return ok;
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
	if (check(p, TOKEN_SEMICOLON)) {
		return NULL;
	}
	if (match(p, TOKEN_LET)) {
		return parse_binding_statement(p, 0);
	}
	if (match(p, TOKEN_VAR)) {
		return parse_binding_statement(p, 1);
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

	/* Support `for cond { ... }` as a while-style loop. */
	if (!check(p, TOKEN_LPAREN)) {
		if (!check(p, TOKEN_LBRACE)) {
			node->as.for_stmt.condition = parse_expression(p);
			if (!node->as.for_stmt.condition) {
				ast_free(node);
				return NULL;
			}
		}
		if (!expect(p, TOKEN_LBRACE, "{")) {
			ast_free(node);
			return NULL;
		}
		node->as.for_stmt.body = parse_block(p);
		if (!node->as.for_stmt.body) {
			ast_free(node);
			return NULL;
		}
		return node;
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

static int try_parse_type_annotation(parser *p, char **out_type) {
	char *parsed = NULL;
	size_t saved = p->current;

	if (check(p, TOKEN_LBRACKET)) {
		size_t inner_start;
		char *inner = NULL;
		char *tail = NULL;
		size_t need;
		int depth;

		advance_tok(p);
		if (match(p, TOKEN_RBRACKET)) {
			if (!try_parse_type_annotation(p, &tail)) {
				p->current = saved;
				return 0;
			}
			need = strlen(tail) + 3;
			parsed = (char *)malloc(need);
			if (!parsed) {
				error_set(p->err, ERR_OUT_OF_MEMORY, peek(p)->pos.line, peek(p)->pos.column, "out of memory");
				free(tail);
				p->current = saved;
				return 0;
			}
			snprintf(parsed, need, "[]%s", tail);
			free(tail);
			*out_type = parsed;
			return 1;
		}

		inner_start = p->current;
		depth = 1;
		while (depth > 0 && !is_at_end(p)) {
			if (check(p, TOKEN_LBRACKET)) {
				depth++;
				advance_tok(p);
				continue;
			}
			if (check(p, TOKEN_RBRACKET)) {
				depth--;
				if (depth == 0) {
					break;
				}
				advance_tok(p);
				continue;
			}
			advance_tok(p);
		}
		if (depth != 0) {
			p->current = saved;
			return 0;
		}

		inner = join_lexemes_range(p->tokens, inner_start, p->current);
		if (!inner) {
			error_set(p->err, ERR_OUT_OF_MEMORY, peek(p)->pos.line, peek(p)->pos.column, "out of memory");
			p->current = saved;
			return 0;
		}
		if (!expect(p, TOKEN_RBRACKET, "]")) {
			free(inner);
			p->current = saved;
			return 0;
		}
		if (!try_parse_type_annotation(p, &tail)) {
			free(inner);
			p->current = saved;
			return 0;
		}

		need = strlen(inner) + strlen(tail) + 3;
		parsed = (char *)malloc(need);
		if (!parsed) {
			error_set(p->err, ERR_OUT_OF_MEMORY, peek(p)->pos.line, peek(p)->pos.column, "out of memory");
			free(inner);
			free(tail);
			p->current = saved;
			return 0;
		}
		snprintf(parsed, need, "[%s]%s", inner, tail);
		free(inner);
		free(tail);
	} else if (match(p, TOKEN_IDENTIFIER)) {
		size_t need;
		char *next_parsed = NULL;
		parsed = dup_cstr(prev(p)->lexeme);
		if (!parsed) {
			error_set(p->err, ERR_OUT_OF_MEMORY, prev(p)->pos.line, prev(p)->pos.column, "out of memory");
			return 0;
		}
		while (check(p, TOKEN_LBRACKET)) {
			size_t inner_start;
			char *inner = NULL;
			int depth;
			advance_tok(p);
			inner_start = p->current;
			depth = 1;
			while (depth > 0 && !is_at_end(p)) {
				if (check(p, TOKEN_LBRACKET)) {
					depth++;
					advance_tok(p);
					continue;
				}
				if (check(p, TOKEN_RBRACKET)) {
					depth--;
					if (depth == 0) {
						break;
					}
					advance_tok(p);
					continue;
				}
				advance_tok(p);
			}
			if (depth != 0) {
				free(parsed);
				p->current = saved;
				return 0;
			}
			inner = join_lexemes_range(p->tokens, inner_start, p->current);
			if (!inner) {
				error_set(p->err, ERR_OUT_OF_MEMORY, peek(p)->pos.line, peek(p)->pos.column, "out of memory");
				free(parsed);
				p->current = saved;
				return 0;
			}
			if (!expect(p, TOKEN_RBRACKET, "]")) {
				free(inner);
				free(parsed);
				p->current = saved;
				return 0;
			}
			need = strlen(parsed) + strlen(inner) + 3;
			next_parsed = (char *)malloc(need);
			if (!next_parsed) {
				error_set(p->err, ERR_OUT_OF_MEMORY, peek(p)->pos.line, peek(p)->pos.column, "out of memory");
				free(inner);
				free(parsed);
				p->current = saved;
				return 0;
			}
			snprintf(next_parsed, need, "%s[%s]", parsed, inner);
			free(inner);
			free(parsed);
			parsed = next_parsed;
		}
		if (check(p, TOKEN_IDENTIFIER) || check(p, TOKEN_LBRACKET)) {
			char *tail = NULL;
			if (try_parse_type_annotation(p, &tail)) {
				need = strlen(parsed) + strlen(tail) + 1;
				next_parsed = (char *)malloc(need);
				if (!next_parsed) {
					error_set(p->err, ERR_OUT_OF_MEMORY, peek(p)->pos.line, peek(p)->pos.column, "out of memory");
					free(tail);
					free(parsed);
					p->current = saved;
					return 0;
				}
				snprintf(next_parsed, need, "%s%s", parsed, tail);
				free(tail);
				free(parsed);
				parsed = next_parsed;
			}
		}
	} else {
		return 0;
	}

	*out_type = parsed;
	return 1;
}

static int try_parse_typed_name(parser *p, token_type terminator, char **out_type, char **out_name) {
	size_t saved = p->current;
	size_t start = p->current;
	size_t last_ident = (size_t)-1;
	int bracket_depth = 0;
	int paren_depth = 0;
	int brace_depth = 0;

	*out_type = NULL;
	*out_name = NULL;

	while (!is_at_end(p)) {
		token_type t = peek(p)->type;
		if (t == terminator && bracket_depth == 0 && paren_depth == 0 && brace_depth == 0) {
			break;
		}
		if (terminator == TOKEN_COMMA && t == TOKEN_RPAREN && bracket_depth == 0 && paren_depth == 0 && brace_depth == 0) {
			break;
		}
		if (terminator == TOKEN_COMMA && t == TOKEN_COMMA && bracket_depth == 0 && paren_depth == 0 && brace_depth == 0) {
			break;
		}
		if (terminator == TOKEN_RPAREN && t == TOKEN_RPAREN && bracket_depth == 0 && paren_depth == 0 && brace_depth == 0) {
			break;
		}
		if (t == TOKEN_LBRACKET) {
			bracket_depth++;
		} else if (t == TOKEN_RBRACKET) {
			if (bracket_depth > 0) {
				bracket_depth--;
			}
		} else if (t == TOKEN_LPAREN) {
			paren_depth++;
		} else if (t == TOKEN_RPAREN) {
			if (paren_depth > 0) {
				paren_depth--;
			}
		} else if (t == TOKEN_LBRACE) {
			brace_depth++;
		} else if (t == TOKEN_RBRACE) {
			if (brace_depth > 0) {
				brace_depth--;
			}
		}
		if (t == TOKEN_IDENTIFIER) {
			last_ident = p->current;
		}
		advance_tok(p);
	}

	if (last_ident == (size_t)-1 || last_ident == start) {
		p->current = saved;
		return 0;
	}

	*out_name = dup_cstr(p->tokens->data[last_ident].lexeme);
	if (!*out_name) {
		error_set(p->err, ERR_OUT_OF_MEMORY, p->tokens->data[last_ident].pos.line, p->tokens->data[last_ident].pos.column, "out of memory");
		p->current = saved;
		return 0;
	}

	*out_type = join_lexemes_range(p->tokens, start, last_ident);
	if (!*out_type) {
		error_set(p->err, ERR_OUT_OF_MEMORY, p->tokens->data[start].pos.line, p->tokens->data[start].pos.column, "out of memory");
		free(*out_name);
		*out_name = NULL;
		p->current = saved;
		return 0;
	}

	return 1;
}

static char *join_lexemes_range(const token_vec *tokens, size_t start, size_t end) {
	size_t i;
	size_t total = 0;
	char *out;
	char *cursor;

	if (end < start) {
		return dup_cstr("");
	}

	for (i = start; i < end; i++) {
		total += strlen(tokens->data[i].lexeme);
	}

	out = (char *)malloc(total + 1);
	if (!out) {
		return NULL;
	}

	cursor = out;
	for (i = start; i < end; i++) {
		size_t n = strlen(tokens->data[i].lexeme);
		memcpy(cursor, tokens->data[i].lexeme, n);
		cursor += n;
	}
	*cursor = '\0';
	return out;
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
		size_t saved = p->current;
		param_name = NULL;
		param_type = NULL;

		/* Preferred form: <type> <name>, e.g. []float data / int n */
		if (!error_is_set(p->err) && try_parse_typed_name(p, TOKEN_COMMA, &param_type, &param_name)) {
			/* parsed successfully */
		} else {
			/* Fallback: <name> [type] for older scripts. */
			p->current = saved;
			if (param_type) {
				free(param_type);
				param_type = NULL;
			}
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
			{
				char *parsed_type = NULL;
				if (try_parse_type_annotation(p, &parsed_type)) {
					free(param_type);
					param_type = parsed_type;
				}
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

	if (check(p, TOKEN_LPAREN)) {
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
	} else {
		size_t saved = p->current;
		char *parsed_type = NULL;
		if (try_parse_type_annotation(p, &parsed_type) && check(p, TOKEN_LBRACE)) {
			free(node->as.fn_stmt.return_type);
			node->as.fn_stmt.return_type = parsed_type;
		} else {
			if (parsed_type) {
				free(parsed_type);
			}
			p->current = saved;
		}
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
		if (looks_like_typed_binding(p)) {
			return parse_typed_binding_statement(p, 0);
		}
		return parse_binding_statement(p, 0);
	}
	if (match(p, TOKEN_VAR)) {
		if (looks_like_typed_binding(p)) {
			return parse_typed_binding_statement(p, 1);
		}
		return parse_binding_statement(p, 1);
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
		if (strcmp(tok->lexeme, "extern") == 0) {
			return parse_extern_decl(p);
		}
		if (strcmp(tok->lexeme, "struct") == 0) {
			return parse_struct_decl(p);
		}
		if (strcmp(tok->lexeme, "enum") == 0 ||
			strcmp(tok->lexeme, "trait") == 0 ||
			strcmp(tok->lexeme, "impl") == 0 ||
			strcmp(tok->lexeme, "const") == 0) {
			parse_error(p, tok, "unsupported top-level declaration '%s' in seed compiler", tok->lexeme);
			return NULL;
		}
	}
	return parse_statement(p);
}

static ast_node *parse_extern_decl(parser *p) {
	const token *kw = peek(p);
	ast_node *node;
	int depth;

	if (!match(p, TOKEN_IDENTIFIER) || strcmp(prev(p)->lexeme, "extern") != 0) {
		parse_error(p, peek(p), "expected 'extern'");
		return NULL;
	}

	if (check(p, TOKEN_STRING)) {
		advance_tok(p);
	}

	if (!match(p, TOKEN_FN)) {
		parse_error(p, peek(p), "expected 'func' after extern");
		return NULL;
	}

	if (!expect(p, TOKEN_IDENTIFIER, "extern function name")) {
		return NULL;
	}
	if (!expect(p, TOKEN_LPAREN, "'(' after extern function name")) {
		return NULL;
	}

	depth = 1;
	while (depth > 0 && !is_at_end(p)) {
		if (match(p, TOKEN_LPAREN)) {
			depth++;
			continue;
		}
		if (match(p, TOKEN_RPAREN)) {
			depth--;
			continue;
		}
		advance_tok(p);
	}
	if (depth != 0) {
		parse_error(p, kw, "unterminated extern parameter list");
		return NULL;
	}

	if (check(p, TOKEN_LPAREN)) {
		advance_tok(p);
		depth = 1;
		while (depth > 0 && !is_at_end(p)) {
			if (match(p, TOKEN_LPAREN)) {
				depth++;
				continue;
			}
			if (match(p, TOKEN_RPAREN)) {
				depth--;
				continue;
			}
			advance_tok(p);
		}
		if (depth != 0) {
			parse_error(p, kw, "unterminated extern return type");
			return NULL;
		}
	}

	consume_optional_semicolon(p);
	node = ast_new(AST_PACKAGE_DECL, kw->pos);
	if (!node) {
		return NULL;
	}
	node->as.package_decl.name = dup_cstr("");
	if (!node->as.package_decl.name) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_struct_decl(parser *p) {
	const token *kw = peek(p);
	const token *name_tok;
	ast_node *node;
	int depth;

	if (!match(p, TOKEN_IDENTIFIER) || strcmp(prev(p)->lexeme, "struct") != 0) {
		parse_error(p, peek(p), "expected 'struct'");
		return NULL;
	}

	if (!expect(p, TOKEN_IDENTIFIER, "struct name")) {
		return NULL;
	}
	name_tok = prev(p);

	if (!expect(p, TOKEN_LBRACE, "'{' after struct name")) {
		return NULL;
	}

	depth = 1;
	while (depth > 0 && !is_at_end(p)) {
		if (match(p, TOKEN_LBRACE)) {
			depth++;
			continue;
		}
		if (match(p, TOKEN_RBRACE)) {
			depth--;
			continue;
		}
		advance_tok(p);
	}

	if (depth != 0) {
		parse_error(p, kw, "unterminated struct declaration");
		return NULL;
	}

	consume_optional_semicolon(p);

	/* Minimal support: register struct name as a placeholder symbol for later references. */
	node = ast_new(AST_LET_STMT, kw->pos);
	if (!node) {
		return NULL;
	}
	node->as.let_stmt.name = dup_cstr(name_tok->lexeme);
	if (!node->as.let_stmt.name) {
		ast_free(node);
		return NULL;
	}
	node->as.let_stmt.value = ast_new(AST_NUMBER_EXPR, kw->pos);
	if (!node->as.let_stmt.value) {
		ast_free(node);
		return NULL;
	}
	node->as.let_stmt.value->as.number_expr.literal = dup_cstr("0");
	if (!node->as.let_stmt.value->as.number_expr.literal) {
		ast_free(node);
		return NULL;
	}
	return node;
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
				const token *tok = peek(&p);
				error_set(err, ERR_SYNTAX, tok->pos.line, tok->pos.column,
				          "failed to parse top-level near '%s'", tok->lexeme ? tok->lexeme : "<eof>");
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

static ast_node *parse_struct_literal_expr(parser *p, const token *type_tok) {
	ast_node *node;
	char **next_names;

	if (!expect(p, TOKEN_LBRACE, "{")) {
		return NULL;
	}

	node = ast_new(AST_STRUCT_EXPR, type_tok->pos);
	if (!node) {
		return NULL;
	}
	node->as.struct_expr.type_name = dup_cstr(type_tok->lexeme);
	if (!node->as.struct_expr.type_name) {
		ast_free(node);
		return NULL;
	}

	while (!check(p, TOKEN_RBRACE)) {
		ast_node *value;
		if (!expect(p, TOKEN_IDENTIFIER, "struct field name")) {
			ast_free(node);
			return NULL;
		}
		next_names = (char **)realloc(
			node->as.struct_expr.field_names,
			(node->as.struct_expr.field_count + 1) * sizeof(char *)
		);
		if (!next_names) {
			error_set(p->err, ERR_OUT_OF_MEMORY, prev(p)->pos.line, prev(p)->pos.column, "out of memory");
			ast_free(node);
			return NULL;
		}
		node->as.struct_expr.field_names = next_names;
		node->as.struct_expr.field_names[node->as.struct_expr.field_count] = dup_cstr(prev(p)->lexeme);
		if (!node->as.struct_expr.field_names[node->as.struct_expr.field_count]) {
			ast_free(node);
			return NULL;
		}
		if (!expect(p, TOKEN_COLON, ":")) {
			ast_free(node);
			return NULL;
		}
		value = parse_expression(p);
		if (!value) {
			ast_free(node);
			return NULL;
		}
		if (!ast_vec_push(&node->as.struct_expr.field_values, value)) {
			ast_free(value);
			ast_free(node);
			return NULL;
		}
		node->as.struct_expr.field_count++;
		if (!match(p, TOKEN_COMMA)) {
			break;
		}
		if (check(p, TOKEN_RBRACE)) {
			break;
		}
	}

	if (!expect(p, TOKEN_RBRACE, "}")) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static ast_node *parse_map_literal_expr(parser *p, const token *type_tok, const char *type_name) {
	ast_node *node;
	char **next_names;

	if (!expect(p, TOKEN_LBRACE, "{")) {
		return NULL;
	}

	node = ast_new(AST_STRUCT_EXPR, type_tok->pos);
	if (!node) {
		return NULL;
	}
	node->as.struct_expr.type_name = dup_cstr(type_name);
	if (!node->as.struct_expr.type_name) {
		ast_free(node);
		return NULL;
	}

	while (!check(p, TOKEN_RBRACE)) {
		ast_node *value;
		const token *key_tok = peek(p);
		if (check(p, TOKEN_STRING) || check(p, TOKEN_IDENTIFIER) || check(p, TOKEN_NUMBER)) {
			advance_tok(p);
		} else {
			parse_error(p, key_tok, "expected map key");
			ast_free(node);
			return NULL;
		}
		next_names = (char **)realloc(
			node->as.struct_expr.field_names,
			(node->as.struct_expr.field_count + 1) * sizeof(char *)
		);
		if (!next_names) {
			error_set(p->err, ERR_OUT_OF_MEMORY, key_tok->pos.line, key_tok->pos.column, "out of memory");
			ast_free(node);
			return NULL;
		}
		node->as.struct_expr.field_names = next_names;
		node->as.struct_expr.field_names[node->as.struct_expr.field_count] = dup_cstr(key_tok->lexeme);
		if (!node->as.struct_expr.field_names[node->as.struct_expr.field_count]) {
			ast_free(node);
			return NULL;
		}
		if (!expect(p, TOKEN_COLON, ":")) {
			ast_free(node);
			return NULL;
		}
		value = parse_expression(p);
		if (!value) {
			ast_free(node);
			return NULL;
		}
		if (!ast_vec_push(&node->as.struct_expr.field_values, value)) {
			ast_free(value);
			ast_free(node);
			return NULL;
		}
		node->as.struct_expr.field_count++;
		if (!match(p, TOKEN_COMMA)) {
			break;
		}
		if (check(p, TOKEN_RBRACE)) {
			break;
		}
	}

	if (!expect(p, TOKEN_RBRACE, "}")) {
		ast_free(node);
		return NULL;
	}
	return node;
}

static int looks_like_struct_literal(parser *p) {
	size_t saved = p->current;
	int brace_depth = 0;
	int paren_depth = 0;
	int bracket_depth = 0;
	int expect_field_name = 1;
	int saw_field = 0;

	if (!match(p, TOKEN_LBRACE)) {
		return 0;
	}
	brace_depth = 1;
	while (brace_depth > 0 && !is_at_end(p)) {
		if (match(p, TOKEN_LBRACE)) {
			brace_depth++;
			continue;
		}
		if (match(p, TOKEN_RBRACE)) {
			brace_depth--;
			continue;
		}
		if (match(p, TOKEN_LPAREN)) {
			paren_depth++;
			continue;
		}
		if (paren_depth > 0 && match(p, TOKEN_RPAREN)) {
			paren_depth--;
			continue;
		}
		if (match(p, TOKEN_LBRACKET)) {
			bracket_depth++;
			continue;
		}
		if (bracket_depth > 0 && match(p, TOKEN_RBRACKET)) {
			bracket_depth--;
			continue;
		}
		if (brace_depth == 1 && paren_depth == 0 && bracket_depth == 0) {
			if (expect_field_name) {
				if (!match(p, TOKEN_IDENTIFIER)) {
					p->current = saved;
					return 0;
				}
				if (!match(p, TOKEN_COLON)) {
					p->current = saved;
					return 0;
				}
				expect_field_name = 0;
				saw_field = 1;
				continue;
			}
			if (match(p, TOKEN_COMMA)) {
				expect_field_name = 1;
				continue;
			}
		}
		advance_tok(p);
	}
	p->current = saved;
	return brace_depth == 0 && paren_depth == 0 && bracket_depth == 0 && saw_field;
}

static int skip_brace_initializer(parser *p) {
	size_t saved = p->current;
	int depth = 0;
	int has_field_colon = 0;

	if (!match(p, TOKEN_LBRACE)) {
		return 1;
	}

	depth = 1;
	while (depth > 0 && !is_at_end(p)) {
		if (match(p, TOKEN_LBRACE)) {
			depth++;
			continue;
		}
		if (match(p, TOKEN_RBRACE)) {
			depth--;
			continue;
		}
		if (depth == 1 && match(p, TOKEN_COLON)) {
			has_field_colon = 1;
			continue;
		}
		advance_tok(p);
	}

	if (depth != 0) {
		error_set(p->err, ERR_SYNTAX, peek(p)->pos.line, peek(p)->pos.column, "Unterminated brace initializer");
		return 0;
	}

	if (!has_field_colon) {
		p->current = saved;
	}

	return 1;
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

	while (check(p, TOKEN_DOT)) {
		size_t saved = p->current;
		advance_tok(p);
		if (allow_selector_suffix && check(p, TOKEN_LBRACE)) {
			p->current = saved;
			break;
		}
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
