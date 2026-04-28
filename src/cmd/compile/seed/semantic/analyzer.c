#include "scope.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef enum symbol_kind {
	SYMBOL_VAR = 0,
	SYMBOL_FN,
	SYMBOL_PARAM,
} symbol_kind;

typedef struct symbol {
	char *name;
	symbol_kind kind;
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
} semantic_ctx;

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
	if (!s) {
		return;
	}
	cur = s->symbols;
	while (cur) {
		next = cur->next;
		free(cur->name);
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

static int scope_define(scope *s, const char *name, symbol_kind kind) {
	symbol *sym;
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
	sym->kind = kind;
	sym->next = s->symbols;
	s->symbols = sym;
	return 1;
}

static int analyze_node(semantic_ctx *ctx, ast_node *node);

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
	if (!enter_child_scope(ctx, &old_scope)) {
		return 0;
	}
	for (i = 0; i < block->as.block.statements.len; i++) {
		if (!analyze_node(ctx, block->as.block.statements.data[i])) {
			leave_child_scope(ctx, old_scope);
			return 0;
		}
	}
	leave_child_scope(ctx, old_scope);
	return 1;
}

static int analyze_node(semantic_ctx *ctx, ast_node *node) {
	size_t i;
	int status;
	if (!node) {
		return 1;
	}

	switch (node->kind) {
		case AST_PROGRAM:
			for (i = 0; i < node->as.program.statements.len; i++) {
				if (!analyze_node(ctx, node->as.program.statements.data[i])) {
					return 0;
				}
			}
			return 1;
		case AST_BLOCK:
			return analyze_block_with_new_scope(ctx, node);
		case AST_LET_STMT:
			if (!analyze_node(ctx, node->as.let_stmt.value)) {
				return 0;
			}
			status = scope_define(ctx->current_scope, node->as.let_stmt.name, SYMBOL_VAR);
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
		case AST_RETURN_STMT:
			if (ctx->function_depth <= 0) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"return statement outside function");
				return 0;
			}
			return analyze_node(ctx, node->as.return_stmt.value);
		case AST_EXPR_STMT:
			return analyze_node(ctx, node->as.expr_stmt.expr);
		case AST_IF_STMT:
			if (!analyze_node(ctx, node->as.if_stmt.condition)) {
				return 0;
			}
			if (!analyze_node(ctx, node->as.if_stmt.then_branch)) {
				return 0;
			}
			return analyze_node(ctx, node->as.if_stmt.else_branch);
		case AST_WHILE_STMT:
			if (!analyze_node(ctx, node->as.while_stmt.condition)) {
				return 0;
			}
			return analyze_node(ctx, node->as.while_stmt.body);
		case AST_FOR_STMT: {
			scope *old_scope;
			if (!enter_child_scope(ctx, &old_scope)) {
				return 0;
			}
			if (!analyze_node(ctx, node->as.for_stmt.init) ||
				!analyze_node(ctx, node->as.for_stmt.condition) ||
				!analyze_node(ctx, node->as.for_stmt.post) ||
				!analyze_node(ctx, node->as.for_stmt.body)) {
				leave_child_scope(ctx, old_scope);
				return 0;
			}
			leave_child_scope(ctx, old_scope);
			return 1;
		}
		case AST_FN_STMT: {
			scope *old_scope;
			status = scope_define(ctx->current_scope, node->as.fn_stmt.name, SYMBOL_FN);
			if (status == 0) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"redefinition of function '%s'", node->as.fn_stmt.name);
				return 0;
			}
			if (status < 0) {
				error_set(ctx->err, ERR_OUT_OF_MEMORY, node->pos.line, node->pos.column, "out of memory");
				return 0;
			}
			if (!enter_child_scope(ctx, &old_scope)) {
				return 0;
			}
			for (i = 0; i < node->as.fn_stmt.param_count; i++) {
				status = scope_define(ctx->current_scope, node->as.fn_stmt.params[i], SYMBOL_PARAM);
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
			ctx->function_depth++;
			if (!analyze_node(ctx, node->as.fn_stmt.body)) {
				ctx->function_depth--;
				leave_child_scope(ctx, old_scope);
				return 0;
			}
			ctx->function_depth--;
			leave_child_scope(ctx, old_scope);
			return 1;
		}
		case AST_BINARY_EXPR:
			return analyze_node(ctx, node->as.binary_expr.left) && analyze_node(ctx, node->as.binary_expr.right);
		case AST_UNARY_EXPR:
			return analyze_node(ctx, node->as.unary_expr.operand);
		case AST_IDENT_EXPR:
			if (!scope_lookup(ctx->current_scope, node->as.ident_expr.name)) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"use of undeclared symbol '%s'", node->as.ident_expr.name);
				return 0;
			}
			return 1;
		case AST_NUMBER_EXPR:
		case AST_STRING_EXPR:
			return 1;
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

	ok = analyze_node(&ctx, root) ? true : false;
	scope_free(global_scope);
	return ok;
}