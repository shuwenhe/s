#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../src/cmd/compile/seed/error/error.h"
#include "../../src/cmd/compile/seed/runtime/memory.h"

bool seed_compile_source_text(const char *, FILE *, compile_error *);

static bool run_case(const char *name, const char *source, const char *diagnostic, long want) {
    compile_error err;
    FILE *stream = tmpfile();
    char ir[32768];
    size_t size;
    long result = -1;
    bool compiled;
    if (!stream) return false;
    error_clear(&err);
    compiled = seed_compile_source_text(source, stream, &err);
    if (diagnostic) {
        fclose(stream);
        if (!compiled && err.code == ERR_SEMANTIC && strstr(err.message, diagnostic)) return true;
        fprintf(stderr, "%s: expected semantic failure containing '%s', got success=%d: %s\n",
            name, diagnostic, compiled, err.message);
        return false;
    }
    if (!compiled) {
        fprintf(stderr, "%s: compile: %s\n", name, err.message);
        fclose(stream);
        return false;
    }
    rewind(stream);
    size = fread(ir, 1, sizeof(ir) - 1, stream);
    fclose(stream);
    ir[size] = '\0';
    if (!strstr(ir, "ARRAY_NEW|") || !strstr(ir, "[]|0")) {
        fprintf(stderr, "%s: missing typed zero-length array construction IR\n", name);
        return false;
    }
    if (!runtime_execute_text(ir, "main", &result, &err) || result != want) {
        fprintf(stderr, "%s: runtime: result=%ld, want=%ld: %s\n", name, result, want, err.message);
        return false;
    }
    return true;
}

int main(void) {
    const struct { const char *name, *source, *diagnostic; long want; } cases[] = {
        {"empty_int", "func main() int { xs := int[](); return len(xs); }", NULL, 0},
        {"typed_push_index", "func main() int { xs := int[](); xs.push(42); return xs[0]; }", NULL, 42},
        {"typed_return", "func empty() int[] { return int[](); } func read(int[] xs) int { return len(xs); } func main() int { return read(empty()); }", NULL, 0},
        {"struct_return", "struct Record { int value } func empty() Record[] { return Record[](); } func main() int { xs := empty(); xs.push(Record { value: 42 }); return xs[0].value; }", NULL, 42},
        {"nested_empty", "func main() int { xs := int[][](); return len(xs); }", NULL, 0},
        {"unknown_type", "func main() int { xs := Missing[](); return 0; }", "unknown array element type", 0},
        {"value_not_type", "func main() int { value := 1; xs := value[](); return 0; }", "unknown array element type", 0},
        {"constructor_arity", "func main() int { xs := int[](1); return 0; }", "expects 0 arguments", 0},
        {"indexed_call", "func main() int { xs := [1]; return xs[0](); }", "call callee must be an identifier", 0},
        {"wrong_push", "func main() int { xs := int[](); xs.push(\"bad\"); return 0; }", "array element type mismatch", 0},
        {"wrong_store", "func main() int { xs := int[](); xs[0] = \"bad\"; return 0; }", "array element type mismatch", 0},
        {"wrong_argument", "func read(string[] xs) int { return len(xs); } func main() int { return read(int[]()); }", "type mismatch", 0},
        {"wrong_return", "func wrong() string[] { return int[](); } func main() int { return 0; }", "type mismatch", 0},
        {"wrong_index_type", "func main() int { xs := int[](); return xs[\"bad\"]; }", "expects int index", 0},
    };
    bool ok = true;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        bool passed = run_case(cases[i].name, cases[i].source, cases[i].diagnostic, cases[i].want);
        printf("%s: %s\n", cases[i].name, passed ? "PASS" : "FAIL");
        ok = passed && ok;
    }
    return ok ? 0 : 1;
}
