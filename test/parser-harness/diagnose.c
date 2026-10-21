#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../src/cmd/compile/seed/code/target.h"
#include "../../src/cmd/compile/seed/lexical/token.h"
#include "../../src/cmd/compile/seed/runtime/memory.h"
#include "../../src/cmd/compile/seed/semantic/scope.h"
#include "../../src/cmd/compile/seed/syntax/ast.h"

/* A phase diagnostic, not a replacement S executor or a Parser PASS gate.
 * Lower the unmodified lexer to inspect the exact failing instruction. Semantic
 * checking is deliberately separate: this test never calls its result checked.
 */
static char *read_text(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); return NULL; }
    long length = ftell(file);
    if (length < 0 || fseek(file, 0, SEEK_SET) != 0) { fclose(file); return NULL; }
    char *text = malloc((size_t)length + 1);
    if (!text) { fclose(file); return NULL; }
    size_t count = fread(text, 1, (size_t)length, file);
    int failed = ferror(file);
    fclose(file);
    if (failed || count != (size_t)length) { free(text); return NULL; }
    text[count] = '\0';
    return text;
}

static int check_address_of(void) {
    const char *source = "func main() int { source := 1; pointer := &source; return 0; }";
    token_vec tokens;
    compile_error err;
    error_clear(&err);
    if (!lexer_scan(source, &tokens, &err)) return 1;
    parse_result parsed = parser_parse_tokens(&tokens, &err);
    token_vec_free(&tokens);
    if (!parsed.root) return 1;
    bool accepted = semantic_analyze(parsed.root, &err);
    parser_parse_result_free(&parsed);
    printf("address-of: accepted=%d error[%d] %zu:%zu %s\n",
        accepted, err.code, err.line, err.column, err.message);
    return accepted || err.code != ERR_SEMANTIC ||
        strcmp(err.message, "unsupported unary operator") != 0;
}

static int check_allocator_dispatch(void) {
    /* Quoting the operand is a diagnostic control only. It removes value
     * resolution from this tiny input so we can test allocator dispatch alone.
     * The real lexer's IR is never rewritten or executed via this control.
     */
    const char *control = "SSEED-TARGET-V1\nFUNC_BEGIN|main|_|_\n"
        "ARG|\"compile.internal.parser.syntax.syntax_lexer\"|_|_\n"
        "CALL|object|alloc|1\nRET|0|_|_\nFUNC_END|main|_|_\n";
    compile_error err;
    long result = -1;
    bool executed = runtime_execute_text(control, "main", &result, &err);
    printf("allocator-dispatch: executed=%d error[%d] %s\n", executed, err.code, err.message);
    return executed || err.code != ERR_SEMANTIC || strcmp(err.message, "unknown function: alloc") != 0;
}

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: diagnose LEXER_SOURCE OUTPUT_IR\n"); return 2; }
    char *source = read_text(argv[1]);
    if (!source) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }
    compile_error err;
    token_vec tokens;
    error_clear(&err);
    if (!lexer_scan(source, &tokens, &err)) { free(source); return 2; }
    free(source);
    parse_result parsed = parser_parse_tokens(&tokens, &err);
    token_vec_free(&tokens);
    if (!parsed.root) { fprintf(stderr, "lexer source parse: %s\n", err.message); return 2; }
    IR ir;
    ir_init(&ir);
    if (!ir_generate_from_ast(parsed.root, &ir, &err)) {
        fprintf(stderr, "lexer source lowering: %s\n", err.message);
        ir_free(&ir);
        parser_parse_result_free(&parsed);
        return 2;
    }
    FILE *output = fopen(argv[2], "wb");
    if (!output) { ir_free(&ir); parser_parse_result_free(&parsed); return 2; }
    generate_code(&ir, output);
    int write_failed = ferror(output);
    int close_failed = fclose(output);
    ir_free(&ir);
    parser_parse_result_free(&parsed);
    if (write_failed || close_failed) return 2;
    char *text = read_text(argv[2]);
    if (!text) return 2;
    int64_t argument = 0, result = -1;
    /* Zero is a sentinel argument. lexer_new fails before reading source:
     * no claim about pointer marshalling follows from this invocation.
     */
    bool executed = runtime_execute_text_i64(text, "lexer_new", &argument, 1, &result, &err);
    free(text);
    printf("real-lexer-new: executed=%d error[%d] %s\n", executed, err.code, err.message);
    int failed = executed || err.code != ERR_SEMANTIC ||
        strcmp(err.message, "unknown arg value: compile.internal.parser.syntax.syntax_lexer") != 0;
    failed |= check_allocator_dispatch();
    failed |= check_address_of();
    puts("Parser Harness=BLOCKED; Pointer/Struct Calling=NOT VERIFIED; AST Assertions=NOT REACHED");
    return failed ? 1 : 0;
}
