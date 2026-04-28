#include "scope.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef enum symbol_kind {
	SYMBOL_VAR = 0,
	SYMBOL_FN,
	SYMBOL_PARAM,
	SYMBOL_IMPORT,
} symbol_kind;

typedef struct symbol {
	char *name;
	symbol_kind kind;
	int arity;
	char *type_name;
	char **param_types;
	size_t param_count;
	struct symbol *next;
} symbol;

typedef struct scope {
	symbol *symbols;
	struct scope *parent;
} scope;

typedef struct semantic_ctx {
	scope *current_scope;
	compile_error *err;
	int function_depth;
	int loop_depth;
	const char *current_return_type;
} semantic_ctx;

typedef enum flow_exit_kind {
	FLOW_EXIT_NONE = 0,
	FLOW_EXIT_RETURN,
	FLOW_EXIT_BREAK,
	FLOW_EXIT_CONTINUE,
	FLOW_EXIT_MIXED,
} flow_exit_kind;

static const char *TYPE_ANY = "any";
static const char *TYPE_INT = "int";
static const char *TYPE_STRING = "string";
static const char *TYPE_BOOL = "bool";
static const char *TYPE_UNIT = "()";

static char *dup_cstr(const char *s) {
	size_t n = strlen(s);
	char *out = (char *)malloc(n + 1);
	if (!out) {
		return NULL;
	}
	memcpy(out, s, n + 1);
	return out;
}

static scope *scope_push(scope *parent) {
	scope *s = (scope *)calloc(1, sizeof(scope));
	if (!s) {
		return NULL;
	}
	s->parent = parent;
	return s;
}

static void scope_free(scope *s) {
	symbol *cur;
	symbol *next;
	size_t i;
	if (!s) {
		return;
	}
	cur = s->symbols;
	while (cur) {
		next = cur->next;
		free(cur->name);
		free(cur->type_name);
		for (i = 0; i < cur->param_count; i++) {
			free(cur->param_types[i]);
		}
		free(cur->param_types);
		free(cur);
		cur = next;
	}
	free(s);
}

static symbol *scope_lookup_current(scope *s, const char *name) {
	symbol *cur = s ? s->symbols : NULL;
	while (cur) {
		if (strcmp(cur->name, name) == 0) {
			return cur;
		}
		cur = cur->next;
	}
	return NULL;
}

static symbol *scope_lookup(scope *s, const char *name) {
	scope *it = s;
	while (it) {
		symbol *sym = scope_lookup_current(it, name);
		if (sym) {
			return sym;
		}
		it = it->parent;
	}
	return NULL;
}

static int scope_define(scope *s,
	const char *name,
	symbol_kind kind,
	int arity,
	const char *type_name,
	char **param_types,
	size_t param_count) {
	symbol *sym;
	size_t i;
	if (!s) {
		return 0;
	}
	if (scope_lookup_current(s, name)) {
		return 0;
	}
	sym = (symbol *)calloc(1, sizeof(symbol));
	if (!sym) {
		return -1;
	}
	sym->name = dup_cstr(name);
	if (!sym->name) {
		free(sym);
		return -1;
	}
	sym->type_name = dup_cstr(type_name ? type_name : TYPE_ANY);
	if (!sym->type_name) {
		free(sym->name);
		free(sym);
		return -1;
	}
	sym->kind = kind;
	sym->arity = arity;
	if (param_count > 0) {
		sym->param_types = (char **)calloc(param_count, sizeof(char *));
		if (!sym->param_types) {
			free(sym->type_name);
			free(sym->name);
			free(sym);
			return -1;
		}
		for (i = 0; i < param_count; i++) {
			sym->param_types[i] = dup_cstr(param_types && param_types[i] ? param_types[i] : TYPE_ANY);
			if (!sym->param_types[i]) {
				while (i > 0) {
					free(sym->param_types[--i]);
				}
				free(sym->param_types);
				free(sym->type_name);
				free(sym->name);
				free(sym);
				return -1;
			}
		}
		sym->param_count = param_count;
	}
	sym->next = s->symbols;
	s->symbols = sym;
	return 1;
}

static int is_type_any(const char *type_name) {
	return !type_name || strcmp(type_name, TYPE_ANY) == 0;
}

static int is_type_assignable(const char *expected, const char *actual) {
	if (is_type_any(expected) || is_type_any(actual)) {
		return 1;
	}
	return strcmp(expected, actual) == 0;
}

static int is_truthy_type(const char *type_name) {
	return is_type_any(type_name) || strcmp(type_name, TYPE_BOOL) == 0 || strcmp(type_name, TYPE_INT) == 0;
}

static int is_ordered_type(const char *type_name) {
	return is_type_any(type_name) || strcmp(type_name, TYPE_INT) == 0 || strcmp(type_name, TYPE_STRING) == 0;
}

static int analyze_node(semantic_ctx *ctx, ast_node *node);
static int analyze_expr(semantic_ctx *ctx, ast_node *node, const char **out_type);

static flow_exit_kind merge_flow_exit_kind(flow_exit_kind a, flow_exit_kind b) {
	if (a == FLOW_EXIT_NONE) {
		return b;
	}
	if (b == FLOW_EXIT_NONE) {
		return a;
	}
	if (a == b) {
		return a;
	}
	return FLOW_EXIT_MIXED;
}

static flow_exit_kind stmt_exit_kind(ast_node *node) {
	if (!node) {
		return FLOW_EXIT_NONE;
	}
	switch (node->kind) {
		case AST_RETURN_STMT:
			return FLOW_EXIT_RETURN;
		case AST_BREAK_STMT:
			return FLOW_EXIT_BREAK;
		case AST_CONTINUE_STMT:
			return FLOW_EXIT_CONTINUE;
		case AST_IF_STMT:
			if (!node->as.if_stmt.else_branch) {
				return FLOW_EXIT_NONE;
			}
			return merge_flow_exit_kind(
				stmt_exit_kind(node->as.if_stmt.then_branch),
				stmt_exit_kind(node->as.if_stmt.else_branch)
			);
		case AST_BLOCK: {
			size_t i;
			flow_exit_kind kind = FLOW_EXIT_NONE;
			for (i = 0; i < node->as.block.statements.len; i++) {
				flow_exit_kind next_kind = stmt_exit_kind(node->as.block.statements.data[i]);
				if (next_kind != FLOW_EXIT_NONE) {
					kind = merge_flow_exit_kind(kind, next_kind);
					if (kind == FLOW_EXIT_MIXED || i + 1 < node->as.block.statements.len) {
						return kind;
					}
				}
			}
			return kind;
		}
		default:
			return FLOW_EXIT_NONE;
	}
}

static int enter_child_scope(semantic_ctx *ctx, scope **old_scope) {
	scope *child;
	*old_scope = ctx->current_scope;
	child = scope_push(ctx->current_scope);
	if (!child) {
		error_set(ctx->err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return 0;
	}
	ctx->current_scope = child;
	return 1;
}

static void leave_child_scope(semantic_ctx *ctx, scope *old_scope) {
	scope *child = ctx->current_scope;
	ctx->current_scope = old_scope;
	scope_free(child);
}

static int analyze_block_with_new_scope(semantic_ctx *ctx, ast_node *block) {
	size_t i;
	scope *old_scope;
	flow_exit_kind terminator = FLOW_EXIT_NONE;
	if (!enter_child_scope(ctx, &old_scope)) {
		return 0;
	}
	for (i = 0; i < block->as.block.statements.len; i++) {
		if (terminator != FLOW_EXIT_NONE) {
			const char *reason = "control transfer";
			if (terminator == FLOW_EXIT_RETURN) {
				reason = "return";
			} else if (terminator == FLOW_EXIT_BREAK) {
				reason = "break";
			} else if (terminator == FLOW_EXIT_CONTINUE) {
				reason = "continue";
			}
			error_set(ctx->err, ERR_SEMANTIC,
				block->as.block.statements.data[i]->pos.line,
				block->as.block.statements.data[i]->pos.column,
				"unreachable statement after %s", reason);
			leave_child_scope(ctx, old_scope);
			return 0;
		}
		if (!analyze_node(ctx, block->as.block.statements.data[i])) {
			leave_child_scope(ctx, old_scope);
			return 0;
		}
		terminator = stmt_exit_kind(block->as.block.statements.data[i]);
	}
	leave_child_scope(ctx, old_scope);
	return 1;
}

static int stmt_guarantees_return(semantic_ctx *ctx, ast_node *node, const char *return_type) {
	size_t i;
	const char *expr_type;
	if (!node) {
		return 0;
	}
	switch (node->kind) {
		case AST_RETURN_STMT:
			return 1;
		case AST_BLOCK:
			for (i = 0; i < node->as.block.statements.len; i++) {
				if (stmt_guarantees_return(ctx, node->as.block.statements.data[i], return_type)) {
					return 1;
				}
			}
			if (node->as.block.statements.len > 0) {
				ast_node *tail = node->as.block.statements.data[node->as.block.statements.len - 1];
				if (tail->kind == AST_EXPR_STMT) {
					if (!analyze_expr(ctx, tail->as.expr_stmt.expr, &expr_type)) {
						return 0;
					}
					if (is_type_assignable(return_type, expr_type)) {
						return 1;
					}
				}
			}
			return 0;
		case AST_IF_STMT:
			if (!node->as.if_stmt.else_branch) {
				return 0;
			}
			return stmt_guarantees_return(ctx, node->as.if_stmt.then_branch, return_type) &&
				stmt_guarantees_return(ctx, node->as.if_stmt.else_branch, return_type);
		default:
			return 0;
	}
}

static int analyze_expr(semantic_ctx *ctx, ast_node *node, const char **out_type) {
	size_t i;
	const char *lhs_type;
	const char *rhs_type;
	symbol *sym;
	if (!node) {
		*out_type = TYPE_UNIT;
		return 1;
	}

	switch (node->kind) {
		case AST_NUMBER_EXPR:
			*out_type = TYPE_INT;
			return 1;
		case AST_BOOL_EXPR:
			*out_type = TYPE_BOOL;
			return 1;
		case AST_STRING_EXPR:
			*out_type = TYPE_STRING;
			return 1;
		case AST_IDENT_EXPR:
			sym = scope_lookup(ctx->current_scope, node->as.ident_expr.name);
			if (!sym) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"use of undeclared symbol '%s'", node->as.ident_expr.name);
				return 0;
			}
			*out_type = sym->type_name;
			return 1;
		case AST_UNARY_EXPR:
			if (!analyze_expr(ctx, node->as.unary_expr.operand, &rhs_type)) {
				return 0;
			}
			if (node->as.unary_expr.op == TOKEN_MINUS) {
				if (!is_type_assignable(TYPE_INT, rhs_type)) {
					error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
						"unary '-' expects int, got '%s'", rhs_type ? rhs_type : TYPE_ANY);
					return 0;
				}
				*out_type = TYPE_INT;
				return 1;
			}
			if (node->as.unary_expr.op == TOKEN_BANG) {
				if (!is_truthy_type(rhs_type)) {
					error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
						"unary '!' expects bool/int, got '%s'", rhs_type ? rhs_type : TYPE_ANY);
					return 0;
				}
				*out_type = TYPE_BOOL;
				return 1;
			}
			error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column, "unsupported unary operator");
			return 0;
		case AST_BINARY_EXPR:
			if (!analyze_expr(ctx, node->as.binary_expr.left, &lhs_type) ||
				!analyze_expr(ctx, node->as.binary_expr.right, &rhs_type)) {
				return 0;
			}
			switch (node->as.binary_expr.op) {
				case TOKEN_PLUS:
					if (is_type_assignable(TYPE_INT, lhs_type) && is_type_assignable(TYPE_INT, rhs_type)) {
						*out_type = TYPE_INT;
						return 1;
					}
					if (is_type_assignable(TYPE_STRING, lhs_type) && is_type_assignable(TYPE_STRING, rhs_type)) {
						*out_type = TYPE_STRING;
						return 1;
					}
					if (is_type_any(lhs_type) || is_type_any(rhs_type)) {
						*out_type = TYPE_ANY;
						return 1;
					}
					error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
						"operator '+' type mismatch: '%s' and '%s'", lhs_type, rhs_type);
					return 0;
				case TOKEN_MINUS:
				case TOKEN_STAR:
				case TOKEN_SLASH:
					if (!is_type_assignable(TYPE_INT, lhs_type) || !is_type_assignable(TYPE_INT, rhs_type)) {
						error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
							"arithmetic operator expects int operands, got '%s' and '%s'", lhs_type, rhs_type);
						return 0;
					}
					*out_type = TYPE_INT;
					return 1;
				case TOKEN_EQ:
				case TOKEN_NE:
					if (!is_type_assignable(lhs_type, rhs_type) && !is_type_assignable(rhs_type, lhs_type)) {
						error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
							"comparison type mismatch: '%s' and '%s'", lhs_type, rhs_type);
						return 0;
					}
					*out_type = TYPE_BOOL;
					return 1;
				case TOKEN_LT:
				case TOKEN_LE:
				case TOKEN_GT:
				case TOKEN_GE:
					if (!is_ordered_type(lhs_type) || !is_ordered_type(rhs_type) ||
						(!is_type_any(lhs_type) && !is_type_any(rhs_type) && strcmp(lhs_type, rhs_type) != 0)) {
						error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
							"ordered comparison type mismatch: '%s' and '%s'", lhs_type, rhs_type);
						return 0;
					}
					*out_type = TYPE_BOOL;
					return 1;
				case TOKEN_AND_AND:
				case TOKEN_OR_OR:
					if (!is_truthy_type(lhs_type) || !is_truthy_type(rhs_type)) {
						error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
							"logical operator expects bool/int operands, got '%s' and '%s'", lhs_type, rhs_type);
						return 0;
					}
					*out_type = TYPE_BOOL;
					return 1;
				default:
					error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
						"unsupported binary operator");
					return 0;
			}
		case AST_ASSIGN_EXPR:
			sym = scope_lookup(ctx->current_scope, node->as.assign_expr.name);
			if (!sym) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"assignment to undeclared symbol '%s'", node->as.assign_expr.name);
				return 0;
			}
			if (sym->kind == SYMBOL_FN || sym->kind == SYMBOL_IMPORT) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"symbol '%s' is not assignable", sym->name);
				return 0;
			}
			if (!analyze_expr(ctx, node->as.assign_expr.value, &rhs_type)) {
				return 0;
			}
			if (!is_type_assignable(sym->type_name, rhs_type)) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"assignment type mismatch for '%s': expected '%s', got '%s'",
					sym->name,
					sym->type_name,
					rhs_type ? rhs_type : TYPE_ANY);
				return 0;
			}
			if (is_type_any(sym->type_name) && !is_type_any(rhs_type)) {
				free(sym->type_name);
				sym->type_name = dup_cstr(rhs_type);
				if (!sym->type_name) {
					error_set(ctx->err, ERR_OUT_OF_MEMORY, node->pos.line, node->pos.column, "out of memory");
					return 0;
				}
			}
			*out_type = sym->type_name;
			return 1;
		case AST_CALL_EXPR:
			if (!node->as.call_expr.callee || node->as.call_expr.callee->kind != AST_IDENT_EXPR) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"call callee must be an identifier");
				return 0;
			}
			sym = scope_lookup(ctx->current_scope, node->as.call_expr.callee->as.ident_expr.name);
			if (!sym) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"call to undeclared symbol '%s'", node->as.call_expr.callee->as.ident_expr.name);
				return 0;
			}
			if (sym->kind == SYMBOL_VAR || sym->kind == SYMBOL_PARAM) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"symbol '%s' is not callable", sym->name);
				return 0;
			}
			if (sym->kind == SYMBOL_FN && sym->arity >= 0 && (size_t)sym->arity != node->as.call_expr.args.len) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"function '%s' expects %d arguments, got %zu", sym->name, sym->arity, node->as.call_expr.args.len);
				return 0;
			}
			for (i = 0; i < node->as.call_expr.args.len; i++) {
				if (!analyze_expr(ctx, node->as.call_expr.args.data[i], &rhs_type)) {
					return 0;
				}
				if (sym->kind == SYMBOL_FN && i < sym->param_count &&
					!is_type_assignable(sym->param_types[i], rhs_type)) {
					error_set(ctx->err, ERR_SEMANTIC, node->as.call_expr.args.data[i]->pos.line,
						node->as.call_expr.args.data[i]->pos.column,
						"argument %zu type mismatch for '%s': expected '%s', got '%s'",
						i + 1,
						sym->name,
						sym->param_types[i],
						rhs_type ? rhs_type : TYPE_ANY);
					return 0;
				}
			}
			*out_type = sym->kind == SYMBOL_FN ? sym->type_name : TYPE_ANY;
			return 1;
		default:
			error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column, "unsupported expression node kind");
			return 0;
	}
}

static int analyze_node(semantic_ctx *ctx, ast_node *node) {
	size_t i;
	int status;
	const char *expr_type;
	symbol *target;
	if (!node) {
		return 1;
	}

	switch (node->kind) {
		case AST_PROGRAM:
			for (i = 0; i < node->as.program.statements.len; i++) {
				ast_node *decl = node->as.program.statements.data[i];
				if (decl->kind == AST_FN_STMT) {
					status = scope_define(
						ctx->current_scope,
						decl->as.fn_stmt.name,
						SYMBOL_FN,
						(int)decl->as.fn_stmt.param_count,
						decl->as.fn_stmt.return_type ? decl->as.fn_stmt.return_type : TYPE_ANY,
						decl->as.fn_stmt.param_types,
						decl->as.fn_stmt.param_count
					);
					if (status == 0) {
						error_set(ctx->err, ERR_SEMANTIC, decl->pos.line, decl->pos.column,
							"redefinition of function '%s'", decl->as.fn_stmt.name);
						return 0;
					}
					if (status < 0) {
						error_set(ctx->err, ERR_OUT_OF_MEMORY, decl->pos.line, decl->pos.column, "out of memory");
						return 0;
					}
				}
				if (decl->kind == AST_USE_DECL && decl->as.use_decl.alias && decl->as.use_decl.alias[0] != '\0') {
					status = scope_define(ctx->current_scope, decl->as.use_decl.alias, SYMBOL_IMPORT, -1, TYPE_ANY, NULL, 0);
					if (status == 0) {
						error_set(ctx->err, ERR_SEMANTIC, decl->pos.line, decl->pos.column,
							"redefinition of import alias '%s'", decl->as.use_decl.alias);
						return 0;
					}
					if (status < 0) {
						error_set(ctx->err, ERR_OUT_OF_MEMORY, decl->pos.line, decl->pos.column, "out of memory");
						return 0;
					}
				}
			}
			for (i = 0; i < node->as.program.statements.len; i++) {
				if (!analyze_node(ctx, node->as.program.statements.data[i])) {
					return 0;
				}
			}
			return 1;
		case AST_PACKAGE_DECL:
		case AST_USE_DECL:
			return 1;
		case AST_BLOCK:
			return analyze_block_with_new_scope(ctx, node);
		case AST_LET_STMT:
			if (!analyze_expr(ctx, node->as.let_stmt.value, &expr_type)) {
				return 0;
			}
			status = scope_define(ctx->current_scope, node->as.let_stmt.name, SYMBOL_VAR, -1, expr_type, NULL, 0);
			if (status == 0) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"redefinition of symbol '%s'", node->as.let_stmt.name);
				return 0;
			}
			if (status < 0) {
				error_set(ctx->err, ERR_OUT_OF_MEMORY, node->pos.line, node->pos.column, "out of memory");
				return 0;
			}
			return 1;
		case AST_ASSIGN_STMT:
			target = scope_lookup(ctx->current_scope, node->as.assign_stmt.name);
			if (!target) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"assignment to undeclared symbol '%s'", node->as.assign_stmt.name);
				return 0;
			}
			if (target->kind == SYMBOL_FN || target->kind == SYMBOL_IMPORT) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"symbol '%s' is not assignable", target->name);
				return 0;
			}
			if (!analyze_expr(ctx, node->as.assign_stmt.value, &expr_type)) {
				return 0;
			}
			if (!is_type_assignable(target->type_name, expr_type)) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"assignment type mismatch for '%s': expected '%s', got '%s'",
					target->name,
					target->type_name,
					expr_type ? expr_type : TYPE_ANY);
				return 0;
			}
			if (is_type_any(target->type_name) && !is_type_any(expr_type)) {
				free(target->type_name);
				target->type_name = dup_cstr(expr_type);
				if (!target->type_name) {
					error_set(ctx->err, ERR_OUT_OF_MEMORY, node->pos.line, node->pos.column, "out of memory");
					return 0;
				}
			}
			return 1;
		case AST_RETURN_STMT:
			if (ctx->function_depth <= 0) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"return statement outside function");
				return 0;
			}
			if (!analyze_expr(ctx, node->as.return_stmt.value, &expr_type)) {
				return 0;
			}
			if (!is_type_assignable(ctx->current_return_type, expr_type)) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"return type mismatch: expected '%s', got '%s'",
					ctx->current_return_type ? ctx->current_return_type : TYPE_ANY,
					expr_type ? expr_type : TYPE_ANY);
				return 0;
			}
			return 1;
		case AST_BREAK_STMT:
			if (ctx->loop_depth <= 0) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column, "break outside loop");
				return 0;
			}
			return 1;
		case AST_CONTINUE_STMT:
			if (ctx->loop_depth <= 0) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column, "continue outside loop");
				return 0;
			}
			return 1;
		case AST_EXPR_STMT:
			return analyze_expr(ctx, node->as.expr_stmt.expr, &expr_type);
		case AST_IF_STMT:
			if (!analyze_expr(ctx, node->as.if_stmt.condition, &expr_type)) {
				return 0;
			}
			if (!is_truthy_type(expr_type)) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"if condition expects bool/int, got '%s'", expr_type ? expr_type : TYPE_ANY);
				return 0;
			}
			if (!analyze_node(ctx, node->as.if_stmt.then_branch)) {
				return 0;
			}
			return analyze_node(ctx, node->as.if_stmt.else_branch);
		case AST_WHILE_STMT:
			if (!analyze_expr(ctx, node->as.while_stmt.condition, &expr_type)) {
				return 0;
			}
			if (!is_truthy_type(expr_type)) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"while condition expects bool/int, got '%s'", expr_type ? expr_type : TYPE_ANY);
				return 0;
			}
			ctx->loop_depth++;
			status = analyze_node(ctx, node->as.while_stmt.body);
			ctx->loop_depth--;
			return status;
		case AST_FOR_STMT: {
			scope *old_scope;
			if (!enter_child_scope(ctx, &old_scope)) {
				return 0;
			}
			if (!analyze_node(ctx, node->as.for_stmt.init)) {
				leave_child_scope(ctx, old_scope);
				return 0;
			}
			if (node->as.for_stmt.condition) {
				if (!analyze_expr(ctx, node->as.for_stmt.condition, &expr_type) || !is_truthy_type(expr_type)) {
					error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
						"for condition expects bool/int");
					leave_child_scope(ctx, old_scope);
					return 0;
				}
			}
			if (!analyze_node(ctx, node->as.for_stmt.post)) {
				leave_child_scope(ctx, old_scope);
				return 0;
			}
			ctx->loop_depth++;
			if (!analyze_node(ctx, node->as.for_stmt.body)) {
				ctx->loop_depth--;
				leave_child_scope(ctx, old_scope);
				return 0;
			}
			ctx->loop_depth--;
			leave_child_scope(ctx, old_scope);
			return 1;
		}
		case AST_FN_STMT: {
			scope *old_scope;
			const char *old_return_type;
			if (!enter_child_scope(ctx, &old_scope)) {
				return 0;
			}
			for (i = 0; i < node->as.fn_stmt.param_count; i++) {
				status = scope_define(
					ctx->current_scope,
					node->as.fn_stmt.params[i],
					SYMBOL_PARAM,
					-1,
					node->as.fn_stmt.param_types ? node->as.fn_stmt.param_types[i] : TYPE_ANY,
					NULL,
					0
				);
				if (status == 0) {
					error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
						"duplicate parameter '%s'", node->as.fn_stmt.params[i]);
					leave_child_scope(ctx, old_scope);
					return 0;
				}
				if (status < 0) {
					error_set(ctx->err, ERR_OUT_OF_MEMORY, node->pos.line, node->pos.column, "out of memory");
					leave_child_scope(ctx, old_scope);
					return 0;
				}
			}
			old_return_type = ctx->current_return_type;
			ctx->current_return_type = node->as.fn_stmt.return_type ? node->as.fn_stmt.return_type : TYPE_ANY;
			ctx->function_depth++;
			if (!analyze_node(ctx, node->as.fn_stmt.body)) {
				ctx->function_depth--;
				ctx->current_return_type = old_return_type;
				leave_child_scope(ctx, old_scope);
				return 0;
			}
			ctx->function_depth--;
			if (strcmp(ctx->current_return_type, TYPE_UNIT) != 0 &&
				!stmt_guarantees_return(ctx, node->as.fn_stmt.body, ctx->current_return_type)) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"function '%s' with return type '%s' does not return on all paths",
					node->as.fn_stmt.name,
					ctx->current_return_type);
				ctx->current_return_type = old_return_type;
				leave_child_scope(ctx, old_scope);
				return 0;
			}
			ctx->current_return_type = old_return_type;
			leave_child_scope(ctx, old_scope);
			return 1;
		}
		case AST_BINARY_EXPR:
		case AST_ASSIGN_EXPR:
		case AST_UNARY_EXPR:
		case AST_IDENT_EXPR:
		case AST_CALL_EXPR:
		case AST_NUMBER_EXPR:
		case AST_BOOL_EXPR:
		case AST_STRING_EXPR:
			return analyze_expr(ctx, node, &expr_type);
	}

	error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column, "unknown AST node kind");
	return 0;
}

bool semantic_analyze(ast_node *root, compile_error *err) {
	semantic_ctx ctx;
	scope *global_scope;
	bool ok;
	error_clear(err);
	global_scope = scope_push(NULL);
	if (!global_scope) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}

	ctx.current_scope = global_scope;
	ctx.err = err;
	ctx.function_depth = 0;
	ctx.loop_depth = 0;
	ctx.current_return_type = TYPE_ANY;

	ok = analyze_node(&ctx, root) ? true : false;
	scope_free(global_scope);
	return ok;
}
