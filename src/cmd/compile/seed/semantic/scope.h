#ifndef S_SEED_SCOPE_H
#define S_SEED_SCOPE_H

#include <stdbool.h>

#include "../error/error.h"
#include "../syntax/ast.h"

bool semantic_analyze(ast_node *root, compile_error *err);
typedef struct compile_unit {
	ast_node **files;
	size_t file_count;
} compile_unit;
bool semantic_analyze_compile_unit(compile_unit *unit, compile_error *err);

bool semantic_collect_types(compile_unit *unit, compile_error *err);

#endif