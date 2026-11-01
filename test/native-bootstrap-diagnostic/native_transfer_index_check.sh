#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-transfer-index.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/check.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static size_t comparisons;
static int counted_strcmp(const char *a, const char *b) {
    comparisons++;
    return strcmp(a, b);
}
#define strcmp counted_strcmp
#include "src/cmd/compile/seed/code/standalone_amd64_backend.c"
#undef strcmp

static void add(standalone_module *m, const char *op, const char *result,
                const char *parameter, const char *value) {
    standalone_ins *x = &m->ir.ins[m->ir.len++];
    snprintf(x->op, sizeof(x->op), "%s", op);
    snprintf(x->result, sizeof(x->result), "%s", result);
    snprintf(x->operand1, sizeof(x->operand1), "%s", parameter);
    snprintf(x->operand2, sizeof(x->operand2), "%s", value);
}
static void expect(standalone_module *m, const char *prefix, const char *fn,
                   const char *parameter, const char *value) {
    const char *got = standalone_transfer(m, prefix, fn, parameter);
    if ((!got != !value) || (got && strcmp(got, value))) {
        fprintf(stderr, "transfer mismatch: %s%s parameter=%s got=%s want=%s\n",
                prefix, fn, parameter ? parameter : "*", got ? got : "NULL",
                value ? value : "NULL");
        exit(1);
    }
}
int main(void) {
    standalone_module *m = calloc(1, sizeof(*m));
    if (!m) return 2;
    for (size_t i = 0; i < 8192; i++) {
        char key[80];
        snprintf(key, sizeof(key), "param-transfer:filler.%zu", i);
        add(m, "NOP", key, "argument", "int");
    }
    add(m, "NOP", "param-transfer:qualified.target", "left", "int");
    add(m, "NOP", "param-transfer:qualified.target", "right", "string");
    add(m, "NOP", "return-transfer:qualified.target", "_", "bool");
    add(m, "NOP", "param-transfer:duplicate", "p", "int");
    add(m, "NOP", "param-transfer:duplicate", "p", "int");
    add(m, "NOP", "return-transfer:conflict", "_", "int");
    add(m, "NOP", "return-transfer:conflict", "_", "string");
    add(m, "NOP", "return-transfer:split", "first", "int");
    add(m, "NOP", "return-transfer:split", "second", "bool");
    add(m, "NOP", "return-transfer:empty", "_", "");
    add(m, "EXPORT", "return-transfer:qualified.target", "_", "invalid");
    add(m, "NOP", "return-transfer:main", "_", "int");
    add(m, "FUNC_BEGIN", "main", "_", "_");
    add(m, "RET", "42", "_", "_");
    add(m, "FUNC_END", "main", "_", "_");
    compile_error error;
    error_clear(&error);
    if (!analyze_module(m, &error)) {
        fprintf(stderr, "fixture rejected: %s\n", error.message);
        return 1;
    }
    expect(m, "param-transfer:", "qualified.target", "left", "int");
    expect(m, "param-transfer:", "qualified.target", "right", "string");
    expect(m, "param-transfer:", "qualified.target", NULL, NULL);
    expect(m, "param-transfer:", "qualified.target", "missing", NULL);
    expect(m, "return-transfer:", "qualified.target", NULL, "bool");
    expect(m, "return-transfer:", "qualified.target.extra", NULL, NULL);
    expect(m, "param-transfer:", "duplicate", "p", NULL);
    expect(m, "return-transfer:", "conflict", NULL, NULL);
    expect(m, "return-transfer:", "split", NULL, NULL);
    expect(m, "return-transfer:", "split", "first", "int");
    expect(m, "return-transfer:", "empty", NULL, "");
    expect(m, "borrow-param:", "missing", "p", NULL);
    comparisons = 0;
    for (size_t i = 0; i < 128; i++) {
        expect(m, "return-transfer:", "qualified.target", NULL, "bool");
        expect(m, "return-transfer:", "absent", NULL, NULL);
    }
    if (comparisons > 20000) {
        fprintf(stderr, "descriptor queries rescan unrelated IR: %zu string comparisons\n", comparisons);
        return 1;
    }
    standalone_free_module(m);
    puts("exact native transfer descriptors, duplicate rejection, bounded lookup: PASS");
    return 0;
}
C
"${CC:-cc}" -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -Wall -Wextra -Werror \
    -ffunction-sections -fdata-sections -I "$root" "$work/check.c" \
    "$root/src/cmd/compile/seed/error/error.c" -Wl,--gc-sections -o "$work/check"
"$work/check"
