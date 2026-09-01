#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "jit_compiler.h"
#include "jit_core.h"
#include "jit_codegen_x86.h"
typedef struct {
    char fn_name[256];
    uint8_t *machine_code;
    size_t code_size;
    uint64_t compile_time_ns;
    int is_valid;
} jit_compiled_entry;
struct jit_compiler {
    jit_cache *cache;
    jit_x86_context *x86_ctx;
    jit_compiled_entry *compiled;
    size_t compiled_count;
    size_t compiled_cap;
    jit_compiler_options opts;
    uint64_t total_compile_time_ns;
    uint64_t total_functions_compiled;
    uint64_t total_functions_executed;
};
jit_compiler *jit_compiler_create(const jit_compiler_options *opts) {
    jit_compiler *jc = (jit_compiler *)malloc(sizeof(*jc));
    if (!jc) return NULL;
    memset(jc, 0, sizeof(*jc));
    if (opts) {
        memcpy(&jc->opts, opts, sizeof(*opts));
    } else {
        jit_compiler_options default_opts = JIT_COMPILER_OPT_DEFAULT;
        memcpy(&jc->opts, &default_opts, sizeof(default_opts));
    }
    if (!jc->opts.enable_jit) {
        return jc;
    }
    jc->cache = jit_cache_create(jc->opts.hotspot_threshold);
    if (!jc->cache) {
        free(jc);
        return NULL;
    }
    jc->x86_ctx = jit_x86_context_create();
    if (!jc->x86_ctx) {
        jit_cache_destroy(jc->cache);
        free(jc);
        return NULL;
    }
    jc->compiled_cap = 16;
    jc->compiled = (jit_compiled_entry *)calloc(jc->compiled_cap, sizeof(*jc->compiled));
    if (!jc->compiled) {
        jit_x86_context_destroy(jc->x86_ctx);
        jit_cache_destroy(jc->cache);
        free(jc);
        return NULL;
    }
    return jc;
}
void jit_compiler_destroy(jit_compiler *jc) {
    if (!jc) return;
    size_t i;
    for (i = 0; i < jc->compiled_count; i++) {
        if (jc->compiled[i].machine_code) {
            jit_free_executable(jc->compiled[i].machine_code, jc->compiled[i].code_size);
        }
    }
    free(jc->compiled);
    jit_x86_context_destroy(jc->x86_ctx);
    jit_cache_destroy(jc->cache);
    free(jc);
}
static jit_compiled_entry *jit_compiler_find_compiled(jit_compiler *jc, const char *fn_name) {
    size_t i;
    for (i = 0; i < jc->compiled_count; i++) {
        if (strcmp(jc->compiled[i].fn_name, fn_name) == 0 && jc->compiled[i].is_valid) {
            return &jc->compiled[i];
        }
    }
    return NULL;
}
int jit_compiler_on_function_enter(jit_compiler *jc, const char *fn_name,
                                   size_t start_pc, size_t end_pc) {
    if (!jc || !jc->opts.enable_jit || !fn_name) return 1;
    jc->total_functions_executed++;
    return jit_cache_record_execution(jc->cache, fn_name, start_pc, end_pc);
}
int jit_compiler_try_compile(jit_compiler *jc, const char *fn_name,
                            size_t start_pc, size_t end_pc,
                            uint8_t **out_code, size_t *out_size) {
    int is_hot;
    uint64_t start_time_ns;
    if (!jc || !jc->opts.enable_jit || !fn_name || !out_code || !out_size) return 0;
    jit_compiled_entry *existing = jit_compiler_find_compiled(jc, fn_name);
    if (existing) {
        *out_code = existing->machine_code;
        *out_size = existing->code_size;
        return 1;
    }
    if (!jit_cache_is_hotspot(jc->cache, fn_name, start_pc, end_pc, &is_hot)) return 0;
    if (!is_hot) return 0;
    start_time_ns = jit_get_timestamp_ns();
    jit_x86_compile_input input = {
        .ir_code = NULL,
        .ir_len = 0,
        .fn_name = fn_name
    };
    uint8_t *compiled_code = NULL;
    size_t compiled_size = 0;
    if (!jit_x86_compile(jc->x86_ctx, &input, &compiled_code, &compiled_size)) {
        return 0;
    }
    if (!jit_make_executable(compiled_code, compiled_size)) {
        jit_free_executable(compiled_code, compiled_size);
        return 0;
    }
    if (jc->compiled_count == jc->compiled_cap) {
        jc->compiled_cap *= 2;
        jit_compiled_entry *next = (jit_compiled_entry *)realloc(jc->compiled,
                                                                  jc->compiled_cap * sizeof(*next));
        if (!next) {
            jit_free_executable(compiled_code, compiled_size);
            return 0;
        }
        jc->compiled = next;
    }
    jit_compiled_entry *entry = &jc->compiled[jc->compiled_count++];
    memset(entry, 0, sizeof(*entry));
    strncpy(entry->fn_name, fn_name, sizeof(entry->fn_name) - 1);
    entry->machine_code = compiled_code;
    entry->code_size = compiled_size;
    entry->compile_time_ns = jit_get_timestamp_ns() - start_time_ns;
    entry->is_valid = 1;
    jc->total_compile_time_ns += entry->compile_time_ns;
    jc->total_functions_compiled++;
    jit_cache_mark_compiled(jc->cache, fn_name, (jit_compiled_code_t)compiled_code);
    if (jc->opts.verbose) {
        fprintf(stderr, "[JIT] Compiled function '%s' in %llu ns\n", fn_name,
               (unsigned long long)entry->compile_time_ns);
    }
    *out_code = compiled_code;
    *out_size = compiled_size;
    return 1;
}
int jit_compiler_is_compiled(jit_compiler *jc, const char *fn_name) {
    if (!jc || !jc->opts.enable_jit || !fn_name) return 0;
    return jit_compiler_find_compiled(jc, fn_name) != NULL;
}
void jit_compiler_dump_stats(jit_compiler *jc) {
    if (!jc || !jc->opts.enable_jit) return;
    fprintf(stderr, "\n=== JIT Statistics ===\n");
    fprintf(stderr, "Functions executed: %llu\n", (unsigned long long)jc->total_functions_executed);
    fprintf(stderr, "Functions compiled: %llu\n", (unsigned long long)jc->total_functions_compiled);
    fprintf(stderr, "Total compilation time: %llu ns (%.2f ms)\n",
           (unsigned long long)jc->total_compile_time_ns,
           (double)jc->total_compile_time_ns / 1000000.0);
    if (jc->total_functions_compiled > 0) {
        fprintf(stderr, "Average compile time: %.2f ns per function\n",
               (double)jc->total_compile_time_ns / (double)jc->total_functions_compiled);
    }
    fprintf(stderr, "Compilation rate: %.2f%%\n",
           (double)jc->total_functions_compiled * 100.0 /
           (double)(jc->total_functions_executed > 0 ? jc->total_functions_executed : 1));
    fprintf(stderr, "=======================\n\n");
}
