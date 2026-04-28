#ifndef S_SEED_SCOPE_H
#define S_SEED_SCOPE_H

#include <stdbool.h>

#include "../error/error.h"
#include "../syntax/ast.h"

bool semantic_analyze(ast_node *root, compile_error *err);

#endif