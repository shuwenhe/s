#ifndef S_SEED_AST_H
#define S_SEED_AST_H

#include <stddef.h>

#include "../lexical/token.h"

typedef enum ast_kind {
	AST_PROGRAM = 0,
	AST_BLOCK,

	AST_LET_STMT,
	AST_ASSIGN_STMT,
	AST_RETURN_STMT,
	AST_BREAK_STMT,
	AST_CONTINUE_STMT,
	AST_EXPR_STMT,
	AST_PACKAGE_DECL,
	AST_USE_DECL,
	AST_IF_STMT,
	AST_WHILE_STMT,
	AST_FOR_STMT,
	AST_FN_STMT,

	AST_BINARY_EXPR,
	AST_ASSIGN_EXPR,
	AST_UNARY_EXPR,
	AST_IDENT_EXPR,
	AST_NUMBER_EXPR,
	AST_BOOL_EXPR,
	AST_STRING_EXPR,
	AST_CALL_EXPR,
} ast_kind;

typedef struct ast_node ast_node;

typedef struct ast_vec {
	ast_node **data;
	size_t len;
	size_t cap;
} ast_vec;

struct ast_node {
	ast_kind kind;
	source_pos pos;

	union {
		struct {
			ast_vec statements;
		} program;

		struct {
			ast_vec statements;
		} block;

		struct {
			char *name;
			ast_node *value;
		} let_stmt;

		struct {
			char *name;
			ast_node *value;
		} assign_stmt;

		struct {
			ast_node *value;
		} return_stmt;

		struct {
			ast_node *expr;
		} expr_stmt;

		struct {
			char *name;
		} package_decl;

		struct {
			char *module_path;
			char *alias;
		} use_decl;

		struct {
			ast_node *condition;
			ast_node *then_branch;
			ast_node *else_branch;
		} if_stmt;

		struct {
			ast_node *condition;
			ast_node *body;
		} while_stmt;

		struct {
			ast_node *init;
			ast_node *condition;
			ast_node *post;
			ast_node *body;
		} for_stmt;

		struct {
			char *name;
			char **params;
			char **param_types;
			size_t param_count;
			char *return_type;
			ast_node *body;
		} fn_stmt;

		struct {
			token_type op;
			ast_node *left;
			ast_node *right;
		} binary_expr;

		struct {
			char *name;
			ast_node *value;
		} assign_expr;

		struct {
			token_type op;
			ast_node *operand;
		} unary_expr;

		struct {
			char *name;
		} ident_expr;

		struct {
			char *literal;
		} number_expr;

		struct {
			int value;
		} bool_expr;

		struct {
			char *literal;
		} string_expr;

		struct {
			ast_node *callee;
			ast_vec args;
		} call_expr;
	} as;
};

const char *ast_kind_name(ast_kind kind);

ast_node *ast_new(ast_kind kind, source_pos pos);
void ast_free(ast_node *node);

void ast_vec_init(ast_vec *vec);
int ast_vec_push(ast_vec *vec, ast_node *node);
void ast_vec_free(ast_vec *vec);

typedef struct parse_result {
	ast_node *root;
} parse_result;

struct compile_error;
parse_result parser_parse_tokens(const token_vec *tokens, struct compile_error *err);
void parser_parse_result_free(parse_result *res);

#endif