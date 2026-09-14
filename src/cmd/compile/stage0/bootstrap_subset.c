/* Bootstrap subset v1; contract: doc/bootstrap-subset.md. Embedded in Stage1. */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE 1
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

enum { BS_EOF = 256, BS_NAME, BS_INT, BS_STRING, BS_WALRUS };

typedef struct {
    char name[64];
    int value;
} BsLocal;

typedef struct {
    char name[64];
    int is_call;
    int value;
    char callee[64];
    BsLocal locals[256];
    int local_count;
} BsFunction;
typedef struct {
    const char *source, *cursor;
    int token, number, failed;
    char name[64];
    char string_value[256];
    char package_name[64];
    BsFunction functions[256];
    int count, entry;
} BsUnit;

static void bs_error(BsUnit *u, const char *message) {
    if (!u->failed)
        fprintf(stderr, "bootstrap-subset: byte %zu: %s\n",
                (size_t)(u->cursor - u->source), message);
    u->failed = 1;
}

static void bs_next(BsUnit *u) {
    const char *p = u->cursor;
    if (u->failed) return;
    for (;;) {
        while (isspace((unsigned char)*p)) p++;
        if (p[0] == '/' && p[1] == '/') {
            while (*p && *p != '\n') p++;
        } else if (p[0] == '/' && p[1] == '*') {
            p += 2;
            while (*p && !(p[0] == '*' && p[1] == '/')) p++;
            if (!*p) { u->cursor = p; bs_error(u, "unterminated comment"); return; }
            p += 2;
        } else break;
    }
    u->cursor = p;
    if (!*p) { u->token = BS_EOF; return; }
    if (*p == '"') {
        /* String literal */
        size_t n = 0;
        p++;
        while (*p && *p != '"') {
            if (*p == '\\' && p[1]) p++;  /* Skip escape sequences */
            if (n == sizeof(u->string_value) - 1) { bs_error(u, "string too long"); return; }
            u->string_value[n++] = *p++;
        }
        if (!*p) { u->cursor = p; bs_error(u, "unterminated string"); return; }
        u->string_value[n] = 0;
        p++;  /* Skip closing quote */
        u->token = BS_STRING;
    } else if (isalpha((unsigned char)*p) || *p == '_') {
        size_t n = 0;
        while (isalnum((unsigned char)*p) || *p == '_') {
            if (n == sizeof(u->name) - 1) { bs_error(u, "identifier too long"); return; }
            u->name[n++] = *p++;
        }
        u->name[n] = 0;
        u->token = BS_NAME;
    } else if (isdigit((unsigned char)*p)) {
        int value = 0;
        while (isdigit((unsigned char)*p)) {
            int digit = *p++ - '0';
            if (value > (2147483647 - digit) / 10) { bs_error(u, "integer out of range"); return; }
            value = value * 10 + digit;
        }
        if (isalpha((unsigned char)*p) || *p == '_') { bs_error(u, "invalid integer token"); return; }
        u->number = value;
        u->token = BS_INT;
    } else if (p[0] == ':' && p[1] == '=') {
        u->token = BS_WALRUS;
        p += 2;
    } else {
        if (!strchr("(){};", *p)) { bs_error(u, "unsupported character"); return; }
        u->token = (unsigned char)*p++;
    }
    u->cursor = p;
}

static void bs_expect(BsUnit *u, int token) {
    if (u->failed) return;
    if (u->token != token) { bs_error(u, "unexpected token"); return; }
    bs_next(u);
}

static void bs_word(BsUnit *u, const char *word) {
    if (u->failed) return;
    if (u->token != BS_NAME || strcmp(u->name, word)) {
        bs_error(u, "expected bootstrap keyword"); return;
    }
    bs_next(u);
}

static int bs_reserved(const char *name) {
    return !strcmp(name, "package") || !strcmp(name, "func") ||
           !strcmp(name, "int") || !strcmp(name, "return");
}

static void bs_identifier(BsUnit *u, char *name) {
    if (u->failed) return;
    if (u->token != BS_NAME || bs_reserved(u->name)) {
        bs_error(u, "expected identifier"); return;
    }
    strcpy(name, u->name);
    bs_next(u);
}

static void bs_skip_import_decl(BsUnit *u) {
    /* Skip import (...) declaration structurally, without semantic resolution.
       Grammar: import "(" (string_literal)* ")" */
    if (u->failed) return;
    bs_word(u, "import");
    bs_expect(u, '(');
    while (!u->failed && u->token != ')') {
        if (u->token == BS_STRING) {
            bs_next(u);
        } else {
            bs_error(u, "expected string in import block"); return;
        }
    }
    bs_expect(u, ')');
}

static int bs_local_find(BsFunction *f, const char *name) {
    for (int i = 0; i < f->local_count; i++)
        if (!strcmp(f->locals[i].name, name)) return i;
    return -1;
}

static void bs_local_bind(BsFunction *f, const char *name, int value) {
    if (f->local_count >= 256) return;
    strcpy(f->locals[f->local_count].name, name);
    f->locals[f->local_count].value = value;
    f->local_count++;
}

static void bs_local_binding(BsUnit *u, BsFunction *f) {
    /* Parse: identifier := expression
       Binds local variable and stores its value. */
    if (u->failed) return;
    if (u->token != BS_NAME) { bs_error(u, "expected identifier"); return; }
    char local_name[64];
    strcpy(local_name, u->name);
    bs_next(u);
    if (u->token != BS_WALRUS) { bs_error(u, "expected :="); return; }
    bs_next(u);
    
    int local_value = 0;
    if (u->token == BS_INT) {
        local_value = u->number;
        bs_next(u);
    } else if (u->token == BS_NAME) {
        /* Reference to another local */
        int idx = bs_local_find(f, u->name);
        if (idx < 0) { bs_error(u, "undefined local"); return; }
        local_value = f->locals[idx].value;
        bs_next(u);
    } else {
        bs_error(u, "expected integer or identifier in binding");
        return;
    }
    
    /* Skip optional semicolon */
    if (u->token == ';') bs_next(u);
    
    bs_local_bind(f, local_name, local_value);
}

static void bs_expression(BsUnit *u, BsFunction *f, int depth) {
    if (u->failed) return;
    if (u->token == '(') {
        if (depth == 64) { bs_error(u, "expression nesting limit"); return; }
        bs_next(u);
        bs_expression(u, f, depth + 1);
        bs_expect(u, ')');
    } else if (u->token == BS_INT) {
        f->value = u->number;
        bs_next(u);
    } else if (u->token == BS_NAME) {
        /* Check if it's a local variable first */
        int idx = bs_local_find(f, u->name);
        if (idx >= 0) {
            /* It's a local variable - use its value */
            f->value = f->locals[idx].value;
            bs_next(u);
        } else {
            /* It's a function call */
            f->is_call = 1;
            bs_identifier(u, f->callee);
            bs_expect(u, '(');
            bs_expect(u, ')');
        }
    } else {
        bs_error(u, "expected expression");
    }
}

static int bs_find(BsUnit *u, const char *name) {
    for (int i = 0; i < u->count; i++)
        if (!strcmp(u->functions[i].name, name)) return i;
    return -1;
}

static void bs_unit(BsUnit *u) {
    bs_next(u);
    bs_word(u, "package");
    bs_identifier(u, u->package_name);
    while (!u->failed && u->token != BS_EOF) {
        /* Structurally skip import declarations before parsing functions */
        if (u->token == BS_NAME && !strcmp(u->name, "import")) {
            bs_skip_import_decl(u);
            continue;
        }
        if (u->count == 256) { bs_error(u, "function count limit"); return; }
        BsFunction *f = &u->functions[u->count];
        bs_word(u, "func");
        bs_identifier(u, f->name);
        if (u->failed) return;
        if (bs_find(u, f->name) >= 0) { bs_error(u, "duplicate function"); return; }
        u->count++;
        f->local_count = 0;  /* Initialize local variable count */
        bs_expect(u, '(');
        bs_expect(u, ')');
        bs_word(u, "int");
        bs_expect(u, '{');
        
        /* Parse local binding statements before return */
        while (!u->failed && u->token != '}' && !(u->token == BS_NAME && !strcmp(u->name, "return"))) {
            bs_local_binding(u, f);
        }
        
        bs_word(u, "return");
        bs_expression(u, f, 0);
        if (u->token == ';') bs_next(u);
        bs_expect(u, '}');
    }
    if (u->failed) return;
    u->entry = bs_find(u, "main");
    if (u->entry < 0) { bs_error(u, "missing main"); return; }
    for (int i = 0; i < u->count; i++) {
        BsFunction *f = &u->functions[i];
        if (f->is_call) {
            f->value = bs_find(u, f->callee);
            if (f->value < 0) { bs_error(u, "undefined function"); return; }
        }
    }
    /* One outgoing call per body: a chain longer than the unit is cyclic. */
    for (int i = 0; i < u->count; i++) {
        int target = i, steps = 0;
        while (u->functions[target].is_call) {
            if (steps++ == u->count) { bs_error(u, "cyclic calls outside bootstrap subset"); return; }
            target = u->functions[target].value;
        }
    }
}

static int bs_emit(BsUnit *u, const char *output) {
    char directory[4096], cpath[4096], native[4096];
    int n = snprintf(directory, sizeof(directory), "%s.bootstrap.XXXXXX", output);
    if (n < 0 || n >= (int)sizeof(directory) - 16) return 1;
    if (!mkdtemp(directory)) { perror("bootstrap-subset: temporary directory"); return 1; }
    snprintf(cpath, sizeof(cpath), "%s/unit.c", directory);
    snprintf(native, sizeof(native), "%s/native", directory);
    int result = 1;
    FILE *c = fopen(cpath, "wb");
    if (!c) goto done;
    for (int i = 0; i < u->count; i++) fprintf(c, "int bs_fn_%d(void);\n", i);
    for (int i = 0; i < u->count; i++) {
        BsFunction *f = &u->functions[i];
        fprintf(c, "int bs_fn_%d(void) { return ", i);
        if (f->is_call) fprintf(c, "bs_fn_%d()", f->value);
        else fprintf(c, "%d", f->value);
        fputs("; }\n", c);
    }
    fprintf(c, "int main(void) { return bs_fn_%d(); }\n", u->entry);
    int write_failed = ferror(c);
    if (fclose(c) != 0 || write_failed) goto done;
    pid_t child = fork();
    if (child < 0) goto done;
    if (child == 0) {
        execlp("cc", "cc", "-std=c11", "-O0", "-Wall", "-Wextra", "-Werror",
               "-o", native, cpath, (char *)NULL);
        perror("bootstrap-subset: cc");
        _exit(127);
    }
    int status;
    pid_t waited;
    do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
    if (waited != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0) goto done;
    if (rename(native, output) != 0) { perror("bootstrap-subset: output"); goto done; }
    result = 0;
done:
    unlink(cpath);
    unlink(native);
    rmdir(directory);
    if (result) fprintf(stderr, "bootstrap-subset: native emission failed\n");
    return result;
}

static int bootstrap_subset_build(const char *input, const char *output) {
    FILE *fp = fopen(input, "rb");
    if (!fp) { perror("bootstrap-subset: input"); return 1; }
    long length;
    if (fseek(fp, 0, SEEK_END) != 0 || (length = ftell(fp)) < 0 ||
        fseek(fp, 0, SEEK_SET) != 0) { fclose(fp); return 1; }
    char *source = malloc((size_t)length + 1);
    BsUnit *unit = calloc(1, sizeof(*unit));
    if (!source || !unit) { free(source); free(unit); fclose(fp); return 1; }
    size_t got = fread(source, 1, (size_t)length, fp);
    int read_failed = ferror(fp);
    fclose(fp);
    if (got != (size_t)length || read_failed || memchr(source, 0, got)) {
        fprintf(stderr, "bootstrap-subset: invalid source bytes\n");
        free(source); free(unit); return 1;
    }
    source[got] = 0;
    unit->source = unit->cursor = source;
    bs_unit(unit);
    int result = unit->failed ? 1 : bs_emit(unit, output);
    free(unit);
    free(source);
    return result;
}
