#ifndef S_SEED_ENUM_TYPE_H
#define S_SEED_ENUM_TYPE_H
#include "ast.h"
#include <stdio.h>
#include <string.h>

/* Enum declarations stay authoritative in the parsed unit. This lookup is
 * shared by checking and lowering; it does not define a native enum ABI. */
static inline int seed_enum_owner_name(const ast_node *node, char *out, size_t cap) {
	int n;
	if (!node) return 0;
	if (node->kind == AST_IDENT_EXPR) {
		n = snprintf(out, cap, "%s", node->as.ident_expr.name);
		return n >= 0 && (size_t)n < cap;
	}
	if (node->kind == AST_INDEX_EXPR)
		return seed_enum_owner_name(node->as.index_expr.object, out, cap);
	if (node->kind == AST_MEMBER_EXPR) {
		char parent[512];
		if (!seed_enum_owner_name(node->as.member_expr.object, parent, sizeof(parent))) return 0;
		n = snprintf(out, cap, "%s.%s", parent, node->as.member_expr.member);
		return n >= 0 && (size_t)n < cap;
	}
	return 0;
}

static inline int seed_enum_decl_name(ast_node *root, const ast_node *decl, char *out, size_t cap) {
	const char *package = "";
	if (!root || root->kind != AST_PROGRAM || !decl || decl->kind != AST_ENUM_DECL) return 0;
	for (size_t i = 0; i < root->as.program.statements.len; i++) {
		ast_node *node = root->as.program.statements.data[i];
		if (node->kind == AST_PACKAGE_DECL) package = node->as.package_decl.name;
		if (node == decl) {
			int n = snprintf(out, cap, "%s%s%s", package, *package ? "." : "", decl->as.enum_decl.name);
			return n >= 0 && (size_t)n < cap;
		}
	}
	return 0;
}

static inline ast_node *seed_find_enum(ast_node *root, const char *owner) {
	size_t n;
	ast_node *short_match = NULL;
	int ambiguous = 0;
	const char *package = "";
	if (!root || root->kind != AST_PROGRAM || !owner) return NULL;
	n = strcspn(owner, "[*");
	for (size_t i = 0; i < root->as.program.statements.len; i++) {
		ast_node *decl = root->as.program.statements.data[i];
		char qualified[1024];
		if (decl->kind == AST_PACKAGE_DECL) package = decl->as.package_decl.name;
		if (decl->kind != AST_ENUM_DECL) continue;
		int size = snprintf(qualified, sizeof(qualified), "%s%s%s", package, *package ? "." : "", decl->as.enum_decl.name);
		if (size >= 0 && (size_t)size < sizeof(qualified) && strlen(qualified) == n &&
			!strncmp(qualified, owner, n)) return decl;
		if (strlen(decl->as.enum_decl.name) == n && !strncmp(decl->as.enum_decl.name, owner, n)) {
			if (short_match) ambiguous = 1;
			else short_match = decl;
		}
	}
	return ambiguous ? NULL : short_match;
}

static inline ast_enum_variant *seed_find_variant(ast_node *decl, const char *name) {
	size_t i;
	if (!decl || !name) return NULL;
	for (i = 0; i < decl->as.enum_decl.variant_count; i++)
		if (strcmp(decl->as.enum_decl.variants[i].name, name) == 0)
			return &decl->as.enum_decl.variants[i];
	return NULL;
}

static inline int seed_enum_has_payload(ast_node *decl) {
	size_t i;
	for (i = 0; i < decl->as.enum_decl.variant_count; i++)
		if (decl->as.enum_decl.variants[i].payload_type) return 1;
	return 0;
}
#endif
