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

typedef enum s_target_os {
	S_TARGET_OS_UNKNOWN = 0,
	S_TARGET_OS_LINUX,
	S_TARGET_OS_DARWIN,
	S_TARGET_OS_WINDOWS
} s_target_os;

typedef enum s_target_arch {
	S_TARGET_ARCH_UNKNOWN = 0,
	S_TARGET_ARCH_AMD64,
	S_TARGET_ARCH_ARM64,
	S_TARGET_ARCH_386
} s_target_arch;

typedef struct s_target_platform {
	s_target_os os;
	s_target_arch arch;
} s_target_platform;

void generate_code(IR *ir, FILE *output);
bool emit_native_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err);
bool emit_standalone_amd64_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err);
bool emit_standalone_amd64_assembly_from_ir_file(const char *input_ir_path, const char *output_assembly_path, compile_error *err);
bool emit_standalone_amd64_object_from_ir_file(const char *input_ir_path, const char *output_object_path, compile_error *err);
bool emit_c_abi_shared_from_ir_file(const char *input_ir_path, const char *output_library_path, compile_error *err);
const char *s_target_backend_name(s_target_backend backend);
bool s_target_backend_probe(s_target_backend backend, char *detail, size_t detail_size);
bool s_target_platform_from_environment(s_target_platform *target, char *detail, size_t detail_size);
bool s_target_platform_parse(const char *text, s_target_platform *target, char *detail, size_t detail_size);
bool s_target_platform_supports_standalone(const s_target_platform *target);
const char *s_target_os_name(s_target_os os);
const char *s_target_arch_name(s_target_arch arch);
const char *s_target_object_format(const s_target_platform *target);
#endif
