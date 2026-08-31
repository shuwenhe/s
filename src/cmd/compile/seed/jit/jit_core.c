#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include "jit_core.h"

jit_cache *jit_cache_create(uint64_t hotspot_threshold) {
    jit_cache *cache = (jit_cache *)malloc(sizeof(*cache));
    if (!cache) return NULL;
    
    memset(cache, 0, sizeof(*cache));
    cache->default_threshold = hotspot_threshold > 0 ? hotspot_threshold : JIT_HOTSPOT_THRESHOLD_DEFAULT;
    cache->cap = 16;
    cache->spots = (jit_hotspot *)calloc(cache->cap, sizeof(*cache->spots));
    
    if (!cache->spots) {
        free(cache);
        return NULL;
    }
    
    return cache;
}

void jit_cache_destroy(jit_cache *cache) {
    if (!cache) return;
    
    size_t i;
    for (i = 0; i < cache->count; i++) {
        if (cache->spots[i].fn_name) {
            free((void *)cache->spots[i].fn_name);
        }
    }
    
    free(cache->spots);
    free(cache);
}

static jit_hotspot *jit_cache_find_or_add(jit_cache *cache, const char *fn_name,
                                          size_t start_pc, size_t end_pc) {
    size_t i;
    
    for (i = 0; i < cache->count; i++) {
        if (cache->spots[i].start_pc == start_pc && 
            cache->spots[i].end_pc == end_pc &&
            strcmp(cache->spots[i].fn_name, fn_name) == 0) {
            return &cache->spots[i];
        }
    }
    
    if (cache->count == cache->cap) {
        cache->cap *= 2;
        jit_hotspot *next = (jit_hotspot *)realloc(cache->spots, cache->cap * sizeof(*next));
        if (!next) return NULL;
        cache->spots = next;
    }
    
    jit_hotspot *spot = &cache->spots[cache->count++];
    memset(spot, 0, sizeof(*spot));
    spot->fn_name = (const char *)malloc(strlen(fn_name) + 1);
    if (!spot->fn_name) {
        cache->count--;
        return NULL;
    }
    strcpy((char *)spot->fn_name, fn_name);
    spot->start_pc = start_pc;
    spot->end_pc = end_pc;
    spot->hotspot_threshold = cache->default_threshold;
    spot->exec_count = 0;
    spot->is_compiled = 0;
    spot->compiled_fn = NULL;
    
    return spot;
}

int jit_cache_record_execution(jit_cache *cache, const char *fn_name,
                               size_t start_pc, size_t end_pc) {
    if (!cache || !fn_name) return 0;
    
    jit_hotspot *spot = jit_cache_find_or_add(cache, fn_name, start_pc, end_pc);
    if (!spot) return 0;
    
    spot->exec_count++;
    return 1;
}

int jit_cache_is_hotspot(jit_cache *cache, const char *fn_name,
                        size_t start_pc, size_t end_pc, int *out_is_hot) {
    if (!cache || !fn_name || !out_is_hot) return 0;
    
    jit_hotspot *spot = jit_cache_find_or_add(cache, fn_name, start_pc, end_pc);
    if (!spot) return 0;
    
    *out_is_hot = (spot->exec_count >= spot->hotspot_threshold && !spot->is_compiled);
    return 1;
}

void jit_cache_mark_compiled(jit_cache *cache, const char *fn_name,
                            jit_compiled_code_t compiled) {
    if (!cache || !fn_name || !compiled) return;
    
    size_t i;
    for (i = 0; i < cache->count; i++) {
        if (strcmp(cache->spots[i].fn_name, fn_name) == 0) {
            cache->spots[i].is_compiled = 1;
            cache->spots[i].compiled_fn = compiled;
            break;
        }
    }
}

jit_code_buffer *jit_codebuf_create(size_t initial_size) {
    if (initial_size == 0) initial_size = 4096;
    
    jit_code_buffer *buf = (jit_code_buffer *)malloc(sizeof(*buf));
    if (!buf) return NULL;
    
    memset(buf, 0, sizeof(*buf));
    buf->code_buf = (uint8_t *)malloc(initial_size);
    if (!buf->code_buf) {
        free(buf);
        return NULL;
    }
    
    buf->code_cap = initial_size;
    buf->code_size = 0;
    
    return buf;
}

void jit_codebuf_destroy(jit_code_buffer *buf) {
    if (!buf) return;
    free(buf->code_buf);
    free(buf->relocs);
    free(buf);
}

static int jit_codebuf_ensure_space(jit_code_buffer *buf, size_t needed) {
    if (buf->code_size + needed <= buf->code_cap) return 1;
    
    size_t new_cap = buf->code_cap * 2;
    while (new_cap < buf->code_size + needed) new_cap *= 2;
    
    uint8_t *next = (uint8_t *)realloc(buf->code_buf, new_cap);
    if (!next) return 0;
    
    buf->code_buf = next;
    buf->code_cap = new_cap;
    return 1;
}

int jit_codebuf_emit_byte(jit_code_buffer *buf, uint8_t byte) {
    if (!buf) return 0;
    if (!jit_codebuf_ensure_space(buf, 1)) return 0;
    
    buf->code_buf[buf->code_size++] = byte;
    return 1;
}

int jit_codebuf_emit_int32(jit_code_buffer *buf, int32_t val) {
    if (!buf) return 0;
    if (!jit_codebuf_ensure_space(buf, 4)) return 0;
    
    uint8_t *ptr = &buf->code_buf[buf->code_size];
    ptr[0] = (val >> 0) & 0xff;
    ptr[1] = (val >> 8) & 0xff;
    ptr[2] = (val >> 16) & 0xff;
    ptr[3] = (val >> 24) & 0xff;
    buf->code_size += 4;
    return 1;
}

int jit_codebuf_emit_int64(jit_code_buffer *buf, int64_t val) {
    if (!buf) return 0;
    if (!jit_codebuf_ensure_space(buf, 8)) return 0;
    
    uint8_t *ptr = &buf->code_buf[buf->code_size];
    ptr[0] = (val >> 0) & 0xff;
    ptr[1] = (val >> 8) & 0xff;
    ptr[2] = (val >> 16) & 0xff;
    ptr[3] = (val >> 24) & 0xff;
    ptr[4] = (val >> 32) & 0xff;
    ptr[5] = (val >> 40) & 0xff;
    ptr[6] = (val >> 48) & 0xff;
    ptr[7] = (val >> 56) & 0xff;
    buf->code_size += 8;
    return 1;
}

int jit_codebuf_append_reloc(jit_code_buffer *buf, size_t offset) {
    if (!buf) return 0;
    
    if (buf->reloc_count == buf->reloc_cap) {
        size_t new_cap = buf->reloc_cap ? buf->reloc_cap * 2 : 8;
        size_t *next = (size_t *)realloc(buf->relocs, new_cap * sizeof(*next));
        if (!next) return 0;
        buf->relocs = next;
        buf->reloc_cap = new_cap;
    }
    
    buf->relocs[buf->reloc_count++] = offset;
    return 1;
}

uint8_t *jit_codebuf_finalize(jit_code_buffer *buf, size_t *out_size) {
    if (!buf || !out_size) return NULL;
    
    uint8_t *result = buf->code_buf;
    *out_size = buf->code_size;
    
    buf->code_buf = NULL;
    buf->code_size = 0;
    buf->code_cap = 0;
    
    return result;
}

int jit_make_executable(uint8_t *code, size_t size) {
    if (!code || size == 0) return 0;
    
    uintptr_t addr = (uintptr_t)code;
    uintptr_t page_size = 4096;
    uintptr_t aligned_addr = addr & ~(page_size - 1);
    size_t aligned_size = ((addr + size + page_size - 1) & ~(page_size - 1)) - aligned_addr;
    
    return mprotect((void *)aligned_addr, aligned_size, PROT_READ | PROT_EXEC) == 0;
}

void jit_free_executable(uint8_t *code, size_t size) {
    if (!code) return;
    mprotect(code, size, PROT_READ | PROT_WRITE);
    free(code);
}

uint64_t jit_get_timestamp_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;
    }
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}
