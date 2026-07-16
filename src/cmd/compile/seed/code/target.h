#ifndef S_SEED_TARGET_H
#define S_SEED_TARGET_H

#include <stdio.h>

#include "../intermediate/ir.h"
#include "../error/error.h"

typedef enum s_target_backend {
	S_TARGET_NATIVE = 0,
	S_TARGET_C_ABI,
	S_TARGET_CUDA,
	S_TARGET_CANN
} s_target_backend;

void generate_code(IR *ir, FILE *output);
bool emit_native_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err);
bool emit_c_abi_shared_from_ir_file(const char *input_ir_path, const char *output_library_path, compile_error *err);
const char *s_target_backend_name(s_target_backend backend);
bool s_target_backend_probe(s_target_backend backend, char *detail, size_t detail_size);

#endif
