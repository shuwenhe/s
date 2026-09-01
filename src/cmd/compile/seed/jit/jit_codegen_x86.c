#include <stdlib.h>
#include <string.h>
#include "jit_codegen_x86.h"
#include "jit_core.h"
struct jit_x86_context {
    size_t label_count;
    size_t var_count;
};
jit_x86_context *jit_x86_context_create(void) {
    jit_x86_context *ctx = (jit_x86_context *)malloc(sizeof(*ctx));
    if (ctx) {
        ctx->label_count = 0;
        ctx->var_count = 0;
    }
    return ctx;
}
void jit_x86_context_destroy(jit_x86_context *ctx) {
    free(ctx);
}
int jit_x86_emit_function_prologue(jit_code_buffer *buf, size_t param_count) {
    if (!buf) return 0;
    jit_codebuf_emit_byte(buf, 0x48);
    jit_codebuf_emit_byte(buf, 0x89);
    jit_codebuf_emit_byte(buf, 0xe5);
    jit_codebuf_emit_byte(buf, 0x48);
    jit_codebuf_emit_byte(buf, 0x83);
    jit_codebuf_emit_byte(buf, 0xec);
    jit_codebuf_emit_byte(buf, 0x10);
    return 1;
}
int jit_x86_emit_function_epilogue(jit_code_buffer *buf) {
    if (!buf) return 0;
    jit_codebuf_emit_byte(buf, 0x48);
    jit_codebuf_emit_byte(buf, 0x83);
    jit_codebuf_emit_byte(buf, 0xc4);
    jit_codebuf_emit_byte(buf, 0x10);
    jit_codebuf_emit_byte(buf, 0xc9);
    jit_codebuf_emit_byte(buf, 0xc3);
    return 1;
}
int jit_x86_emit_mov_reg_imm64(jit_code_buffer *buf, int reg, int64_t imm) {
    if (!buf) return 0;
    jit_codebuf_emit_byte(buf, 0x48);
    jit_codebuf_emit_byte(buf, 0xb8 + reg);
    jit_codebuf_emit_int64(buf, imm);
    return 1;
}
int jit_x86_emit_add_reg_reg(jit_code_buffer *buf, int dst_reg, int src_reg) {
    if (!buf) return 0;
    jit_codebuf_emit_byte(buf, 0x48);
    jit_codebuf_emit_byte(buf, 0x01);
    jit_codebuf_emit_byte(buf, 0xc0 | (src_reg << 3) | dst_reg);
    return 1;
}
int jit_x86_emit_sub_reg_reg(jit_code_buffer *buf, int dst_reg, int src_reg) {
    if (!buf) return 0;
    jit_codebuf_emit_byte(buf, 0x48);
    jit_codebuf_emit_byte(buf, 0x29);
    jit_codebuf_emit_byte(buf, 0xc0 | (src_reg << 3) | dst_reg);
    return 1;
}
int jit_x86_emit_mul_reg_reg(jit_code_buffer *buf, int dst_reg, int src_reg) {
    if (!buf) return 0;
    jit_codebuf_emit_byte(buf, 0x48);
    jit_codebuf_emit_byte(buf, 0x0f);
    jit_codebuf_emit_byte(buf, 0xaf);
    jit_codebuf_emit_byte(buf, 0xc0 | (dst_reg << 3) | src_reg);
    return 1;
}
int jit_x86_emit_jmp(jit_code_buffer *buf, int32_t offset) {
    if (!buf) return 0;
    jit_codebuf_emit_byte(buf, 0xe9);
    jit_codebuf_emit_int32(buf, offset);
    return 1;
}
int jit_x86_emit_cmp_and_jne(jit_code_buffer *buf, int reg, int64_t imm, int32_t offset) {
    if (!buf) return 0;
    jit_codebuf_emit_byte(buf, 0x48);
    jit_codebuf_emit_byte(buf, 0x81);
    jit_codebuf_emit_byte(buf, 0xf8 | reg);
    jit_codebuf_emit_int32(buf, (int32_t)imm);
    jit_codebuf_emit_byte(buf, 0x75);
    jit_codebuf_emit_int32(buf, offset);
    return 1;
}
int jit_x86_compile(jit_x86_context *ctx, const jit_x86_compile_input *input,
                   uint8_t **out_code, size_t *out_size) {
    if (!ctx || !input || !out_code || !out_size) return 0;
    jit_code_buffer *buf = jit_codebuf_create(4096);
    if (!buf) return 0;
    if (!jit_x86_emit_function_prologue(buf, 0)) {
        jit_codebuf_destroy(buf);
        return 0;
    }
    jit_x86_emit_mov_reg_imm64(buf, JIT_X86_REG_RAX, 0);
    jit_x86_emit_function_epilogue(buf);
    *out_code = jit_codebuf_finalize(buf, out_size);
    jit_codebuf_destroy(buf);
    return *out_code != NULL;
}
