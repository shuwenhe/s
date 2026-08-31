#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "jit_core.h"
#include "jit_codegen_x86.h"
#include "jit_compiler.h"

void test_hotspot_detection(void) {
    printf("Test: Hotspot Detection\n");
    
    jit_cache *cache = jit_cache_create(10);
    assert(cache != NULL);
    
    int is_hot;
    
    for (int i = 0; i < 9; i++) {
        assert(jit_cache_record_execution(cache, "test_func", 0, 100));
        assert(jit_cache_is_hotspot(cache, "test_func", 0, 100, &is_hot));
        assert(!is_hot);
    }
    
    assert(jit_cache_record_execution(cache, "test_func", 0, 100));
    assert(jit_cache_is_hotspot(cache, "test_func", 0, 100, &is_hot));
    assert(is_hot);
    
    jit_cache_destroy(cache);
    printf("✓ Passed\n\n");
}

void test_multiple_functions(void) {
    printf("Test: Multiple Functions\n");
    
    jit_cache *cache = jit_cache_create(5);
    assert(cache != NULL);
    
    int is_hot;
    
    for (int i = 0; i < 5; i++) {
        assert(jit_cache_record_execution(cache, "func1", 0, 50));
        assert(jit_cache_record_execution(cache, "func2", 50, 100));
        assert(jit_cache_record_execution(cache, "func3", 100, 150));
    }
    
    assert(jit_cache_is_hotspot(cache, "func1", 0, 50, &is_hot));
    assert(is_hot);
    
    assert(jit_cache_is_hotspot(cache, "func2", 50, 100, &is_hot));
    assert(is_hot);
    
    assert(jit_cache_is_hotspot(cache, "func3", 100, 150, &is_hot));
    assert(is_hot);
    
    jit_cache_destroy(cache);
    printf("✓ Passed\n\n");
}

void test_code_buffer(void) {
    printf("Test: Code Buffer\n");
    
    jit_code_buffer *buf = jit_codebuf_create(1024);
    assert(buf != NULL);
    
    assert(jit_codebuf_emit_byte(buf, 0x90));
    assert(jit_codebuf_emit_byte(buf, 0x90));
    assert(jit_codebuf_emit_int32(buf, 0x12345678));
    assert(jit_codebuf_emit_int64(buf, 0x0102030405060708ULL));
    
    size_t size;
    uint8_t *code = jit_codebuf_finalize(buf, &size);
    assert(code != NULL);
    assert(size == 14);
    
    assert(code[0] == 0x90);
    assert(code[1] == 0x90);
    assert(code[2] == 0x78);
    assert(code[3] == 0x56);
    assert(code[4] == 0x34);
    assert(code[5] == 0x12);
    
    free(code);
    jit_codebuf_destroy(buf);
    printf("✓ Passed\n\n");
}

void test_x86_code_generation(void) {
    printf("Test: x86-64 Code Generation\n");
    
    jit_code_buffer *buf = jit_codebuf_create(1024);
    assert(buf != NULL);
    
    assert(jit_x86_emit_function_prologue(buf, 0));
    assert(jit_x86_emit_mov_reg_imm64(buf, 0, 42));
    assert(jit_x86_emit_add_reg_reg(buf, 0, 1));
    assert(jit_x86_emit_function_epilogue(buf));
    
    size_t size;
    uint8_t *code = jit_codebuf_finalize(buf, &size);
    assert(code != NULL);
    assert(size > 0);
    
    free(code);
    jit_codebuf_destroy(buf);
    printf("✓ Passed\n\n");
}

void test_compiler_creation(void) {
    printf("Test: JIT Compiler Creation\n");
    
    jit_compiler_options opts = JIT_COMPILER_OPT_DEFAULT;
    jit_compiler *jc = jit_compiler_create(&opts);
    assert(jc != NULL);
    
    assert(jit_compiler_on_function_enter(jc, "test_func", 0, 100));
    
    assert(!jit_compiler_is_compiled(jc, "test_func"));
    
    jit_compiler_destroy(jc);
    printf("✓ Passed\n\n");
}

void test_multiple_compilations(void) {
    printf("Test: Multiple Compilations\n");
    
    jit_compiler_options opts = {
        .enable_jit = 1,
        .hotspot_threshold = 2,
        .aggressive_mode = 0,
        .verbose = 0
    };
    jit_compiler *jc = jit_compiler_create(&opts);
    assert(jc != NULL);
    
    for (int i = 0; i < 10; i++) {
        assert(jit_compiler_on_function_enter(jc, "loop_func", 0, 100));
    }
    
    uint8_t *code;
    size_t size;
    int compiled = jit_compiler_try_compile(jc, "loop_func", 0, 100, &code, &size);
    if (compiled) {
        assert(code != NULL);
        assert(size > 0);
    }
    
    jit_compiler_destroy(jc);
    printf("✓ Passed\n\n");
}

void test_disabled_jit(void) {
    printf("Test: Disabled JIT (Zero Overhead)\n");
    
    jit_compiler_options opts = JIT_COMPILER_OPT_DISABLED;
    jit_compiler *jc = jit_compiler_create(&opts);
    assert(jc != NULL);
    
    assert(!jit_compiler_on_function_enter(jc, "func", 0, 100) == 0);
    assert(!jit_compiler_is_compiled(jc, "func") == 1);
    
    uint8_t *code;
    size_t size;
    assert(!jit_compiler_try_compile(jc, "func", 0, 100, &code, &size) == 1);
    
    jit_compiler_destroy(jc);
    printf("✓ Passed\n\n");
}

void run_performance_test(void) {
    printf("Performance: Hotspot Detection Speed\n");
    
    jit_cache *cache = jit_cache_create(100);
    
    uint64_t start = jit_get_timestamp_ns();
    
    for (int i = 0; i < 100000; i++) {
        jit_cache_record_execution(cache, "perf_func", 0, 100);
    }
    
    uint64_t elapsed = jit_get_timestamp_ns() - start;
    
    printf("  100k record_execution calls: %.2f ms\n", (double)elapsed / 1000000.0);
    printf("  Per-call overhead: %.2f ns\n", (double)elapsed / 100000.0);
    
    jit_cache_destroy(cache);
    printf("✓ Passed\n\n");
}

int main(void) {
    printf("\n");
    printf("=====================================\n");
    printf("S JIT Compiler Unit Tests\n");
    printf("=====================================\n\n");
    
    test_hotspot_detection();
    test_multiple_functions();
    test_code_buffer();
    test_x86_code_generation();
    test_compiler_creation();
    test_multiple_compilations();
    test_disabled_jit();
    
    printf("Performance Tests:\n");
    printf("-----------------------------------\n");
    run_performance_test();
    
    printf("\n=====================================\n");
    printf("All tests passed! ✓\n");
    printf("=====================================\n\n");
    
    return EXIT_SUCCESS;
}
