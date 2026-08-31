#ifndef SEED_JIT_CORE_H
#define SEED_JIT_CORE_H

#include <stdint.h>
#include <stddef.h>
#include <sys/mman.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct jit_compiled_function jit_compiled_function;
typedef struct jit_hotspot jit_hotspot;
typedef struct jit_cache jit_cache;

typedef int (*jit_compiled_code_t)(void *);

typedef struct {
    uint8_t *code_buf;
    size_t code_size;
    size_t code_cap;
    size_t *relocs;
    size_t reloc_count;
    size_t reloc_cap;
} jit_code_buffer;

typedef struct {
    const char *fn_name;
    size_t start_pc;
    size_t end_pc;
    uint64_t exec_count;
    uint64_t hotspot_threshold;
    int is_compiled;
    jit_compiled_code_t compiled_fn;
} jit_hotspot;

typedef struct {
    jit_hotspot *spots;
    size_t count;
    size_t cap;
    uint64_t default_threshold;
} jit_cache;

typedef struct {
    const char *fn_name;
    size_t fn_id;
    uint8_t *machine_code;
    size_t code_size;
    uint64_t creation_time;
    int is_valid;
} jit_compiled_function;

jit_cache *jit_cache_create(uint64_t hotspot_threshold);
void jit_cache_destroy(jit_cache *cache);

int jit_cache_record_execution(jit_cache *cache, const char *fn_name, 
                               size_t start_pc, size_t end_pc);

int jit_cache_is_hotspot(jit_cache *cache, const char *fn_name, 
                        size_t start_pc, size_t end_pc, int *out_is_hot);

void jit_cache_mark_compiled(jit_cache *cache, const char *fn_name, 
                            jit_compiled_code_t compiled);

jit_code_buffer *jit_codebuf_create(size_t initial_size);
void jit_codebuf_destroy(jit_code_buffer *buf);

int jit_codebuf_emit_byte(jit_code_buffer *buf, uint8_t byte);
int jit_codebuf_emit_int32(jit_code_buffer *buf, int32_t val);
int jit_codebuf_emit_int64(jit_code_buffer *buf, int64_t val);

int jit_codebuf_append_reloc(jit_code_buffer *buf, size_t offset);

uint8_t *jit_codebuf_finalize(jit_code_buffer *buf, size_t *out_size);

int jit_make_executable(uint8_t *code, size_t size);
void jit_free_executable(uint8_t *code, size_t size);

uint64_t jit_get_timestamp_ns(void);

#define JIT_HOTSPOT_THRESHOLD_DEFAULT 100
#define JIT_HOTSPOT_THRESHOLD_AGGRESSIVE 10
#define JIT_HOTSPOT_THRESHOLD_CONSERVATIVE 1000

#ifdef __cplusplus
}
#endif

#endif
