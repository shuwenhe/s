#ifndef SEED_JIT_CODEGEN_X86_H
#define SEED_JIT_CODEGEN_X86_H
#include <stdint.h>
#include "jit_core.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct jit_x86_context jit_x86_context;
typedef struct {
    const char *ir_code;
    size_t ir_len;
    const char *fn_name;
} jit_x86_compile_input;
jit_x86_context *jit_x86_context_create(void);
void jit_x86_context_destroy(jit_x86_context *ctx);
int jit_x86_compile(jit_x86_context *ctx, const jit_x86_compile_input *input,
                   uint8_t **out_code, size_t *out_size);
int jit_x86_emit_function_prologue(jit_code_buffer *buf, size_t param_count);
int jit_x86_emit_function_epilogue(jit_code_buffer *buf);
int jit_x86_emit_mov_reg_imm64(jit_code_buffer *buf, int reg, int64_t imm);
int jit_x86_emit_add_reg_reg(jit_code_buffer *buf, int dst_reg, int src_reg);
int jit_x86_emit_sub_reg_reg(jit_code_buffer *buf, int dst_reg, int src_reg);
int jit_x86_emit_mul_reg_reg(jit_code_buffer *buf, int dst_reg, int src_reg);
int jit_x86_emit_jmp(jit_code_buffer *buf, int32_t offset);
int jit_x86_emit_cmp_and_jne(jit_code_buffer *buf, int reg, int64_t imm, int32_t offset);
#define JIT_X86_REG_RAX 0
#define JIT_X86_REG_RCX 1
#define JIT_X86_REG_RDX 2
#define JIT_X86_REG_RBX 3
#define JIT_X86_REG_RSP 4
#define JIT_X86_REG_RBP 5
#define JIT_X86_REG_RSI 6
#define JIT_X86_REG_RDI 7
#ifdef __cplusplus
}
#endif
#endif
