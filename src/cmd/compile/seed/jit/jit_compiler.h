#ifndef SEED_JIT_COMPILER_H
#define SEED_JIT_COMPILER_H

#include <stddef.h>
#include <stdint.h>
#include "jit_core.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct jit_compiler jit_compiler;

typedef struct {
    int enable_jit;
    uint64_t hotspot_threshold;
    int aggressive_mode;
    int verbose;
} jit_compiler_options;

jit_compiler *jit_compiler_create(const jit_compiler_options *opts);
void jit_compiler_destroy(jit_compiler *jc);

int jit_compiler_on_function_enter(jit_compiler *jc, const char *fn_name,
                                   size_t start_pc, size_t end_pc);

int jit_compiler_try_compile(jit_compiler *jc, const char *fn_name,
                            size_t start_pc, size_t end_pc,
                            uint8_t **out_code, size_t *out_size);

int jit_compiler_is_compiled(jit_compiler *jc, const char *fn_name);

void jit_compiler_dump_stats(jit_compiler *jc);

#define JIT_COMPILER_OPT_DEFAULT { 1, JIT_HOTSPOT_THRESHOLD_DEFAULT, 0, 0 }
#define JIT_COMPILER_OPT_AGGRESSIVE { 1, JIT_HOTSPOT_THRESHOLD_AGGRESSIVE, 1, 0 }
#define JIT_COMPILER_OPT_DISABLED { 0, 0, 0, 0 }

#ifdef __cplusplus
}
#endif

#endif
