#include "scope.h"

#include <ctype.h>
#include <stddef.h>
#include <stdio.h>
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
	int min_arity;
	int max_arity;
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
	int short_circuit_rhs_depth;
	const char *current_return_type;
} semantic_ctx;

typedef enum flow_exit_kind {
	FLOW_EXIT_NONE = 0,
	FLOW_EXIT_RETURN,
	FLOW_EXIT_BREAK,
	FLOW_EXIT_CONTINUE,
	FLOW_EXIT_MIXED,
} flow_exit_kind;

typedef struct signature_spec {
	char *name;
	int min_arity;
	int max_arity;
	char *return_type;
} signature_spec;

typedef struct narrow_fact {
	char name[64];
	const char *type_name;
} narrow_fact;

static const char *TYPE_ANY = "any";
static const char *TYPE_INT = "int";
static const char *TYPE_STRING = "string";
static const char *TYPE_BOOL = "bool";
static const char *TYPE_ARRAY = "array";
static const char *TYPE_UNIT = "()";

static const char *IMPORT_SIGNATURE_META_PATH = "src/cmd/compile/seed/semantic/import_signatures.meta";

static const signature_spec builtin_signatures[] = {
	{(char *)"print", 1, -1, (char *)"()"},
	{(char *)"println", 0, -1, (char *)"()"},
	{(char *)"len", 1, 1, (char *)"int"},
};

static signature_spec *import_signatures = NULL;
static size_t import_signatures_len = 0;
static int import_signatures_loaded = 0;

static char *dup_cstr(const char *s) {
	size_t n = strlen(s);
	char *out = (char *)malloc(n + 1);
	if (!out) {
		return NULL;
	}
	memcpy(out, s, n + 1);
	return out;
}

static char *trim_inplace(char *s) {
	char *end;
	while (*s && isspace((unsigned char)*s)) {
		s++;
	}
	end = s + strlen(s);
	while (end > s && isspace((unsigned char)end[-1])) {
		end--;
	}
	*end = '\0';
	return s;
}

static int parse_int_field(const char *s, int *out) {
	char *end;
	long v;
	if (strcmp(s, "*") == 0) {
		*out = -1;
		return 1;
	}
	v = strtol(s, &end, 10);
	if (*s == '\0' || *end != '\0') {
		return 0;
	}
	*out = (int)v;
	return 1;
}

static int load_import_signatures(compile_error *err) {
	FILE *fp;
	char line[512];
	size_t line_no = 0;

	if (import_signatures_loaded) {
		return 1;
	}
	import_signatures_loaded = 1;

	fp = fopen(IMPORT_SIGNATURE_META_PATH, "rb");
	if (!fp) {
		/* Metadata is optional; unknown imports will remain permissive. */
		return 1;
	}

	while (fgets(line, sizeof(line), fp)) {
		char *fields[4] = {0};
		char *p;
		size_t i;
		signature_spec spec;
		signature_spec *next;
		char *trimmed;
		line_no++;
		trimmed = trim_inplace(line);
		if (trimmed[0] == '\0' || trimmed[0] == '#') {
			continue;
		}
		p = trimmed;
		for (i = 0; i < 4; i++) {
			fields[i] = p;
			p = strchr(p, '|');
			if (!p && i < 3) {
				fclose(fp);
				error_set(err, ERR_SEMANTIC, line_no, 1, "invalid import signature record");
				return 0;
			}
			if (p) {
				*p = '\0';
				p++;
			}
			fields[i] = trim_inplace(fields[i]);
		}
		if (fields[0][0] == '\0' || fields[3][0] == '\0') {
			fclose(fp);
			error_set(err, ERR_SEMANTIC, line_no, 1, "import signature fields cannot be empty");
			return 0;
		}
		if (!parse_int_field(fields[1], &spec.min_arity) || !parse_int_field(fields[2], &spec.max_arity)) {
			fclose(fp);
			error_set(err, ERR_SEMANTIC, line_no, 1, "invalid arity in import signature");
			return 0;
		}
		if (spec.max_arity >= 0 && spec.min_arity > spec.max_arity) {
			fclose(fp);
			error_set(err, ERR_SEMANTIC, line_no, 1, "import signature min arity exceeds max arity");
			return 0;
		}
		spec.name = dup_cstr(fields[0]);
		spec.return_type = dup_cstr(fields[3]);
		if (!spec.name || !spec.return_type) {
			free(spec.name);
			free(spec.return_type);
			fclose(fp);
			error_set(err, ERR_OUT_OF_MEMORY, line_no, 1, "out of memory");
			return 0;
		}
		next = (signature_spec *)realloc(import_signatures, (import_signatures_len + 1) * sizeof(signature_spec));
		if (!next) {
			free(spec.name);
			free(spec.return_type);
			fclose(fp);
			error_set(err, ERR_OUT_OF_MEMORY, line_no, 1, "out of memory");
			return 0;
		}
		import_signatures = next;
		import_signatures[import_signatures_len++] = spec;
	}

	fclose(fp);
	return 1;
}

static const signature_spec *find_signature(const signature_spec *table, size_t table_len, const char *name) {
	size_t i;
	for (i = 0; i < table_len; i++) {
		if (strcmp(table[i].name, name) == 0) {
			return &table[i];
		}
	}
	return NULL;
}

static void resolve_import_signature(const char *module_path, int *min_arity, int *max_arity, const char **return_type) {
	const signature_spec *spec = find_signature(import_signatures, import_signatures_len, module_path);
	if (!spec) {
		*min_arity = 0;
		*max_arity = -1;
		*return_type = TYPE_ANY;
		return;
	}
	*min_arity = spec->min_arity;
	*max_arity = spec->max_arity;
	*return_type = spec->return_type;
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
	int min_arity,
	int max_arity,
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
	sym->min_arity = min_arity;
	sym->max_arity = max_arity;
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

static int define_builtins(scope *global_scope, compile_error *err) {
	size_t i;
	for (i = 0; i < sizeof(builtin_signatures) / sizeof(builtin_signatures[0]); i++) {
		const signature_spec *spec = &builtin_signatures[i];
		int status = scope_define(global_scope,
			spec->name,
			SYMBOL_FN,
			spec->min_arity,
			spec->max_arity,
			spec->return_type,
			NULL,
			0);
		if (status == 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "redefinition of builtin '%s'", spec->name);
			return 0;
		}
		if (status < 0) {
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
			return 0;
		}
	}
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

static flow_exit_kind stmt_exit_kind(ast_node *node) {
	flow_exit_kind then_kind;
	flow_exit_kind else_kind;
	size_t i;
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
			then_kind = stmt_exit_kind(node->as.if_stmt.then_branch);
			else_kind = stmt_exit_kind(node->as.if_stmt.else_branch);
			if (then_kind == FLOW_EXIT_NONE || else_kind == FLOW_EXIT_NONE) {
				return FLOW_EXIT_NONE;
			}
			if (then_kind == else_kind) {
				return then_kind;
			}
			return FLOW_EXIT_MIXED;
		case AST_BLOCK:
			for (i = 0; i < node->as.block.statements.len; i++) {
				flow_exit_kind next_kind = stmt_exit_kind(node->as.block.statements.data[i]);
				if (next_kind != FLOW_EXIT_NONE) {
					return next_kind;
				}
			}
			return FLOW_EXIT_NONE;
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

static const char *literal_node_type(ast_node *node) {
	if (!node) {
		return NULL;
	}
	switch (node->kind) {
		case AST_NUMBER_EXPR: return TYPE_INT;
		case AST_STRING_EXPR: return TYPE_STRING;
		case AST_BOOL_EXPR: return TYPE_BOOL;
		default: return NULL;
	}
}

static int add_narrow_fact(narrow_fact *facts, size_t *fact_count, const char *name, const char *type_name) {
	size_t i;
	if (!name || !type_name || name[0] == '\0') {
		return 1;
	}
	for (i = 0; i < *fact_count; i++) {
		if (strcmp(facts[i].name, name) == 0) {
			if (strcmp(facts[i].type_name, type_name) != 0) {
				facts[i].type_name = TYPE_ANY;
			}
			return 1;
		}
	}
	if (*fact_count >= 16) {
		return 1;
	}
	snprintf(facts[*fact_count].name, sizeof(facts[*fact_count].name), "%s", name);
	facts[*fact_count].type_name = type_name;
	(*fact_count)++;
	return 1;
}

static int collect_condition_facts(ast_node *cond, int when_true, narrow_fact *facts, size_t *fact_count) {
	const char *literal_type;
	if (!cond) {
		return 1;
	}
	if (cond->kind == AST_UNARY_EXPR && cond->as.unary_expr.op == TOKEN_BANG) {
		return collect_condition_facts(cond->as.unary_expr.operand, !when_true, facts, fact_count);
	}
	if (cond->kind == AST_BINARY_EXPR) {
		token_type op = cond->as.binary_expr.op;
		if (op == TOKEN_AND_AND) {
			if (when_true) {
				if (!collect_condition_facts(cond->as.binary_expr.left, 1, facts, fact_count)) return 0;
				if (!collect_condition_facts(cond->as.binary_expr.right, 1, facts, fact_count)) return 0;
			}
			return 1;
		}
		if (op == TOKEN_OR_OR) {
			if (!when_true) {
				if (!collect_condition_facts(cond->as.binary_expr.left, 0, facts, fact_count)) return 0;
				if (!collect_condition_facts(cond->as.binary_expr.right, 0, facts, fact_count)) return 0;
			}
			return 1;
		}
		if (op == TOKEN_EQ || op == TOKEN_NE) {
			ast_node *left = cond->as.binary_expr.left;
			ast_node *right = cond->as.binary_expr.right;
			if (left && left->kind == AST_IDENT_EXPR) {
				literal_type = literal_node_type(right);
				if (literal_type) {
					add_narrow_fact(facts, fact_count, left->as.ident_expr.name, literal_type);
				}
			}
			if (right && right->kind == AST_IDENT_EXPR) {
				literal_type = literal_node_type(left);
				if (literal_type) {
					add_narrow_fact(facts, fact_count, right->as.ident_expr.name, literal_type);
				}
			}
			return 1;
		}
	}
	return 1;
}

static int apply_narrow_facts(semantic_ctx *ctx, const narrow_fact *facts, size_t fact_count, source_pos pos) {
	size_t i;
	for (i = 0; i < fact_count; i++) {
		symbol *existing = scope_lookup(ctx->current_scope->parent, facts[i].name);
		int status;
		if (!existing) {
			continue;
		}
		if (existing->kind != SYMBOL_VAR && existing->kind != SYMBOL_PARAM) {
			continue;
		}
		if (!is_type_any(existing->type_name) && !is_type_assignable(existing->type_name, facts[i].type_name)) {
			continue;
		}
		status = scope_define(ctx->current_scope,
			existing->name,
			existing->kind,
			existing->min_arity,
			existing->max_arity,
			is_type_any(existing->type_name) ? facts[i].type_name : existing->type_name,
			existing->param_types,
			existing->param_count);
		if (status == 0) {
			continue;
		}
		if (status < 0) {
			error_set(ctx->err, ERR_OUT_OF_MEMORY, pos.line, pos.column, "out of memory");
			return 0;
		}
	}
	return 1;
}

static int analyze_node_with_narrowing(semantic_ctx *ctx, ast_node *branch, ast_node *cond, int when_true) {
	scope *old_scope;
	narrow_fact facts[16];
	size_t fact_count = 0;
	if (!enter_child_scope(ctx, &old_scope)) {
		return 0;
	}
	if (!collect_condition_facts(cond, when_true, facts, &fact_count)) {
		leave_child_scope(ctx, old_scope);
		return 0;
	}
	if (!apply_narrow_facts(ctx, facts, fact_count, branch ? branch->pos : cond->pos)) {
		leave_child_scope(ctx, old_scope);
		return 0;
	}
	if (!analyze_node(ctx, branch)) {
		leave_child_scope(ctx, old_scope);
		return 0;
	}
	leave_child_scope(ctx, old_scope);
	return 1;
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
		case AST_ARRAY_EXPR:
			for (i = 0; i < node->as.array_expr.items.len; i++) {
				if (!analyze_expr(ctx, node->as.array_expr.items.data[i], &rhs_type)) {
					return 0;
				}
			}
			*out_type = TYPE_ARRAY;
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
		case AST_MEMBER_EXPR:
			if (!analyze_expr(ctx, node->as.member_expr.object, &lhs_type)) {
				return 0;
			}
			*out_type = TYPE_ANY;
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
			if (!analyze_expr(ctx, node->as.binary_expr.left, &lhs_type)) {
				return 0;
			}
			if (node->as.binary_expr.op == TOKEN_AND_AND || node->as.binary_expr.op == TOKEN_OR_OR) {
				ctx->short_circuit_rhs_depth++;
				if (!analyze_expr(ctx, node->as.binary_expr.right, &rhs_type)) {
					ctx->short_circuit_rhs_depth--;
					return 0;
				}
				ctx->short_circuit_rhs_depth--;
			} else {
				if (!analyze_expr(ctx, node->as.binary_expr.right, &rhs_type)) {
					return 0;
				}
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
			if (is_type_any(sym->type_name) && !is_type_any(rhs_type) && ctx->short_circuit_rhs_depth == 0) {
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
			if (sym->min_arity >= 0 && (int)node->as.call_expr.args.len < sym->min_arity) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"call to '%s' expects at least %d arguments, got %zu",
					sym->name,
					sym->min_arity,
					node->as.call_expr.args.len);
				return 0;
			}
			if (sym->max_arity >= 0 && (int)node->as.call_expr.args.len > sym->max_arity) {
				error_set(ctx->err, ERR_SEMANTIC, node->pos.line, node->pos.column,
					"call to '%s' expects at most %d arguments, got %zu",
					sym->name,
					sym->max_arity,
					node->as.call_expr.args.len);
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
			*out_type = sym->type_name;
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
					int min_arity;
					int max_arity;
					const char *ret_type;
					resolve_import_signature(decl->as.use_decl.module_path, &min_arity, &max_arity, &ret_type);
					status = scope_define(ctx->current_scope,
						decl->as.use_decl.alias,
						SYMBOL_IMPORT,
						min_arity,
						max_arity,
						ret_type,
						NULL,
						0);
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
				if (decl->kind == AST_USE_DECL && decl->as.use_decl.selector_count > 0) {
					size_t j;
					for (j = 0; j < decl->as.use_decl.selector_count; j++) {
						char full_path[256];
						int min_arity;
						int max_arity;
						const char *ret_type;
						if (!decl->as.use_decl.selectors[j]) {
							continue;
						}
						if (snprintf(full_path, sizeof(full_path), "%s.%s", decl->as.use_decl.module_path, decl->as.use_decl.selectors[j]) >= (int)sizeof(full_path)) {
							error_set(ctx->err, ERR_SEMANTIC, decl->pos.line, decl->pos.column, "import selector path too long");
							return 0;
						}
						resolve_import_signature(full_path, &min_arity, &max_arity, &ret_type);
						status = scope_define(ctx->current_scope,
							decl->as.use_decl.selectors[j],
							SYMBOL_IMPORT,
							min_arity,
							max_arity,
							ret_type,
							NULL,
							0);
						if (status == 0) {
							error_set(ctx->err, ERR_SEMANTIC, decl->pos.line, decl->pos.column,
								"redefinition of import alias '%s'", decl->as.use_decl.selectors[j]);
							return 0;
						}
						if (status < 0) {
							error_set(ctx->err, ERR_OUT_OF_MEMORY, decl->pos.line, decl->pos.column, "out of memory");
							return 0;
						}
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
			status = scope_define(ctx->current_scope, node->as.let_stmt.name, SYMBOL_VAR, -1, -1, expr_type, NULL, 0);
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
			if (is_type_any(target->type_name) && !is_type_any(expr_type) && ctx->short_circuit_rhs_depth == 0) {
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
			if (!analyze_node_with_narrowing(ctx, node->as.if_stmt.then_branch, node->as.if_stmt.condition, 1)) {
				return 0;
			}
			if (!node->as.if_stmt.else_branch) {
				return 1;
			}
			return analyze_node_with_narrowing(ctx, node->as.if_stmt.else_branch, node->as.if_stmt.condition, 0);
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
			status = analyze_node_with_narrowing(ctx, node->as.while_stmt.body, node->as.while_stmt.condition, 1);
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
			if (node->as.for_stmt.condition) {
				status = analyze_node_with_narrowing(ctx, node->as.for_stmt.body, node->as.for_stmt.condition, 1);
			} else {
				status = analyze_node(ctx, node->as.for_stmt.body);
			}
			ctx->loop_depth--;
			if (!status) {
				leave_child_scope(ctx, old_scope);
				return 0;
			}
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
		case AST_MEMBER_EXPR:
		case AST_CALL_EXPR:
		case AST_NUMBER_EXPR:
		case AST_BOOL_EXPR:
		case AST_STRING_EXPR:
		case AST_ARRAY_EXPR:
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
	if (!load_import_signatures(err)) {
		return false;
	}
	global_scope = scope_push(NULL);
	if (!global_scope) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}

	ctx.current_scope = global_scope;
	ctx.err = err;
	ctx.function_depth = 0;
	ctx.loop_depth = 0;
	ctx.short_circuit_rhs_depth = 0;
	ctx.current_return_type = TYPE_ANY;

	if (!define_builtins(global_scope, err)) {
		scope_free(global_scope);
		return false;
	}

	ok = analyze_node(&ctx, root) ? true : false;
	scope_free(global_scope);
	return ok;
}

static bool load_module_and_add_to_scope(const char *module_path, char **selectors, size_t selector_count, compile_error *err) {
	scope *current_scope = scope_push(NULL); // Push a new scope
	if (!current_scope) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "Failed to allocate scope for module");
		return false;
	}

	for (size_t i = 0; i < selector_count; i++) {
		// Add each selector to the scope
		symbol *sym = (symbol *)calloc(1, sizeof(symbol));
		if (!sym) {
			scope_free(current_scope);
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "Failed to allocate symbol for selector");
			return false;
		}
		sym->name = strdup(selectors[i]);
		sym->kind = SYMBOL_IMPORT;
		sym->type_name = strdup("imported_symbol");
		sym->next = current_scope->symbols;
		current_scope->symbols = sym;
	}

	return true;
}
