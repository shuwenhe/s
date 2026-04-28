#ifndef S_SEED_TARGET_H
#define S_SEED_TARGET_H

#include <stdio.h>

#include "../intermediate/ir.h"
#include "../error/error.h"

void generate_code(IR *ir, FILE *output);
bool emit_native_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err);

#endif