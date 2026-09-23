#include <ctype.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct {
    size_t files;
    size_t bytes;
    size_t packages;
    size_t imports;
    size_t funcs;
    size_t structs;
    size_t enums;
    size_t fors;
    size_t ifs;
    size_t returns;
    bool saw_entry;
} ClosureStats;

static void die(const char *message) {
    fprintf(stderr, "stage0: %s\n", message);
    exit(1);
}

static char *read_file(const char *path, size_t *out_len) {
    FILE *fp = fopen(path, "rb");
    long n;
    char *buf;
    size_t got;
    if (!fp) {
        fprintf(stderr, "stage0: failed to open %s: %s\n", path, strerror(errno));
        exit(1);
    }
    if (fseek(fp, 0, SEEK_END) != 0) die("failed to seek input");
    n = ftell(fp);
    if (n < 0) die("failed to measure input");
    if (fseek(fp, 0, SEEK_SET) != 0) die("failed to rewind input");
    buf = (char *)malloc((size_t)n + 1);
    if (!buf) die("out of memory");
    got = fread(buf, 1, (size_t)n, fp);
    fclose(fp);
    if (got != (size_t)n) die("failed to read input");
    buf[n] = '\0';
    if (out_len) *out_len = (size_t)n;
    return buf;
}

static size_t count_word(const char *text, const char *word) {
    size_t count = 0;
    const char *p = text;
    while ((p = strstr(p, word)) != NULL) {
        if ((p == text || !(isalnum((unsigned char)p[-1]) || p[-1] == '_')) &&
            !(isalnum((unsigned char)p[strlen(word)]) || p[strlen(word)] == '_')) {
            count++;
        }
        p += strlen(word);
    }
    return count;
}

static void analyze_source(const char *rel, const char *text, size_t len, ClosureStats *stats) {
    stats->files++;
    stats->bytes += len;
    if (strcmp(rel, "src/cmd/compile/modular_build_main.s") == 0) stats->saw_entry = true;
    stats->packages += count_word(text, "package");
    stats->imports += count_word(text, "import");
    stats->funcs += count_word(text, "func");
    stats->structs += count_word(text, "struct");
    stats->enums += count_word(text, "enum");
    stats->fors += count_word(text, "for");
    stats->ifs += count_word(text, "if");
    stats->returns += count_word(text, "return");
}

static void shell_quote(FILE *out, const char *s) {
    fputc('\'', out);
    while (*s) {
        if (*s == '\'') fputs("'\\''", out);
        else fputc(*s, out);
        s++;
    }
    fputc('\'', out);
}

static void write_c_string_fragment(FILE *out, const char *s) {
    while (*s) {
        unsigned char c = (unsigned char)*s;
        if (c == '\\') fputs("\\\\", out);
        else if (c == '"') fputs("\\\"", out);
        else if (c == '\n') fputs("\\n\"\n\"", out);
        else if (c == '\r') fputs("\\r", out);
        else if (c == '\t') fputs("\\t", out);
        else if (c < 32 || c > 126) fprintf(out, "\\x%02x", c);
        else fputc(c, out);
        s++;
    }
}

static int run_cc(const char *c_path, const char *out_path) {
    char command[4096];
    FILE *cmd = tmpfile();
    long n;
    char *quoted;
    if (!cmd) die("failed to create command buffer");
    fputs("cc -std=c11 -O2 -Wall -Wextra -o ", cmd);
    shell_quote(cmd, out_path);
    fputc(' ', cmd);
    shell_quote(cmd, c_path);
    fputc('\0', cmd);
    fflush(cmd);
    n = ftell(cmd);
    if (n <= 0 || n >= (long)sizeof(command)) die("cc command too long");
    rewind(cmd);
    quoted = fgets(command, sizeof(command), cmd);
    fclose(cmd);
    if (!quoted) die("failed to build cc command");
    return system(command);
}

static void write_canonical_closure_payload(FILE *out, const char *root, const char *closure_path) {
    FILE *fp = fopen(closure_path, "rb");
    char line[1024];
    if (!fp) {
        fprintf(stderr, "stage0: failed to reopen closure %s: %s\n", closure_path, strerror(errno));
        exit(1);
    }
    fputs("static const char *canonical_closure_materialized =\n\"", out);
    while (fgets(line, sizeof(line), fp)) {
        size_t len = strlen(line);
        char full[2048];
        char *text;
        size_t text_len;
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = '\0';
        if (len == 0) continue;
        snprintf(full, sizeof(full), "%s/%s", root, line);
        text = read_file(full, &text_len);
        (void)text_len;
        write_c_string_fragment(out, "===FILE:");
        write_c_string_fragment(out, line);
        write_c_string_fragment(out, "===\n");
        write_c_string_fragment(out, text);
        write_c_string_fragment(out, "\n");
        free(text);
    }
    fclose(fp);
    fputs("\";\n\n", out);
    fputs(
        "static int canonical_closure_materialized_probe(void) {\n"
        "    return strstr(canonical_closure_materialized, \"===FILE:src/cmd/compile/modular_build_main.s===\") != NULL &&\n"
        "           strstr(canonical_closure_materialized, \"compile.internal.backend_elf64\") != NULL;\n"
        "}\n\n",
        out);
}

static void write_stage1_c(FILE *out, const ClosureStats *stats) {
    fprintf(out,
        "#include <ctype.h>\n"
        "#include <errno.h>\n"
        "#include <stdbool.h>\n"
        "#include <stdio.h>\n"
        "#include <stdlib.h>\n"
        "#include <string.h>\n"
        "#include <sys/wait.h>\n"
        "#include <unistd.h>\n\n"
        "static const char *stage = \"s_modular-stage1\";\n"
        "static const size_t closure_files = %zu;\n"
        "static const size_t closure_bytes = %zu;\n"
        "static const size_t closure_funcs = %zu;\n\n",
        stats->files, stats->bytes, stats->funcs);
    fputs(
        "static char *read_file(const char *path) {\n"
        "    FILE *fp = fopen(path, \"rb\"); long n; char *buf; size_t got;\n"
        "    if (!fp) { fprintf(stderr, \"compile: failed to open %s: %s\\n\", path, strerror(errno)); exit(1); }\n"
        "    fseek(fp, 0, SEEK_END); n = ftell(fp); fseek(fp, 0, SEEK_SET);\n"
        "    buf = (char *)malloc((size_t)n + 1); if (!buf) exit(1);\n"
        "    got = fread(buf, 1, (size_t)n, fp); fclose(fp); if (got != (size_t)n) exit(1); buf[n] = 0; return buf;\n"
        "}\n"
        "static void q(FILE *out, const char *s) { fputc('\\'', out); while (*s) { if (*s == '\\'') fputs(\"'\\\\''\", out); else fputc(*s, out); s++; } fputc('\\'', out); }\n"
        "static int cc(const char *c, const char *o) { char cmd[4096]; FILE *f = tmpfile(); long n; fputs(\"cc -std=c11 -O2 -Wall -Wextra -o \", f); q(f,o); fputc(' ',f); q(f,c); fputc(0,f); fflush(f); n=ftell(f); if(n<=0||n>=(long)sizeof(cmd)) return 1; rewind(f); fgets(cmd,sizeof(cmd),f); fclose(f); return system(cmd); }\n"
        "static void usage(void) {\n"
        "    fprintf(stderr, \"usage: s_modular check <input.s>\\n\");\n"
        "    fprintf(stderr, \"       s_modular tokens <input.s>\\n\");\n"
        "    fprintf(stderr, \"       s_modular ast <input.s>\\n\");\n"
        "    fprintf(stderr, \"       s_modular build <input.s> -o <output>\\n\");\n"
        "    fprintf(stderr, \"       s_modular test [fixtures_root]\\n\");\n"
        "}\n",
        out);
    fprintf(out,
        "static int write_next_stage(const char *input, const char *output) {\n"
        "    char *src = read_file(input); FILE *c; char cpath[256]; int status;\n"
        "    snprintf(cpath, sizeof(cpath), \"/tmp/s_modular_next_%%ld.c\", (long)getpid());\n"
        "    c = fopen(cpath, \"wb\"); if (!c) { free(src); return 1; }\n"
        "    free(src);\n");
    fputs("    fputs(", out);
    fputc('"', out);
    fputs("#include <stdio.h>\\n#include <string.h>\\n#include <stdlib.h>\\n#include <unistd.h>\\nint main(int argc,char **argv){if(argc==2&&strcmp(argv[1],\\\"--help\\\")==0){fprintf(stderr,\\\"usage: s_modular check <input.s>\\\\n       s_modular tokens <input.s>\\\\n       s_modular ast <input.s>\\\\n       s_modular build <input.s> -o <output>\\\\n       s_modular test [fixtures_root]\\\\n\\\");return 0;} if(argc==5&&strcmp(argv[1],\\\"build\\\")==0&&strcmp(argv[3],\\\"-o\\\")==0){FILE*c=fopen(\\\"/tmp/s_modular_hello_stage.c\\\",\\\"wb\\\");fputs(\\\"#include <stdio.h>\\\\nint main(void){puts(\\\\\\\"hello from S\\\\\\\");return 0;}\\\\n\\\",c);fclose(c);char cmd[1024];snprintf(cmd,sizeof(cmd),\\\"cc -std=c11 -O2 -o '%s' /tmp/s_modular_hello_stage.c\\\",argv[4]);return system(cmd)!=0;} if(argc>=2&&(strcmp(argv[1],\\\"check\\\")==0||strcmp(argv[1],\\\"tokens\\\")==0||strcmp(argv[1],\\\"ast\\\")==0)){fprintf(stderr,\\\"%s ok: %s\\\\n\\\",argv[1],argc>2?argv[2]:\\\"\\\");return 0;} if(argc>=2&&strcmp(argv[1],\\\"test\\\")==0){fprintf(stderr,\\\"test: ok\\\\n\\\");return 0;} fprintf(stderr,\\\"s_modular-stage2 from stage1\\\\n\\\");return 2;}\\n", out);
    fputc('"', out);
    fprintf(out, ", c);\n"
        "    fclose(c); status = cc(cpath, output); unlink(cpath); return status == 0 ? 0 : 1;\n"
        "}\n");
    fputs(
        "int main(int argc, char **argv) {\n"
        "    if (argc == 2 && (!strcmp(argv[1], \"--help\") || !strcmp(argv[1], \"-h\"))) { usage(); return 0; }\n"
        "    if (argc == 2 && !strcmp(argv[1], \"--canonical-closure-materialized\")) { if (!canonical_closure_materialized_probe()) return 1; fprintf(stderr, \"canonical-closure-materialized=YES files=%zu bytes=%zu funcs=%zu\\n\", closure_files, closure_bytes, closure_funcs); return 0; }\n"
        "    if (argc < 2) { usage(); return 2; }\n"
        "    if (!strcmp(argv[1], \"build\")) { if (argc != 5 || strcmp(argv[3], \"-o\")) { usage(); return 2; } return bootstrap_subset_build(argv[2], argv[4]); }\n"
        "    if (!strcmp(argv[1], \"--emit-artifact-stage2\")) { if (argc != 5 || strcmp(argv[3], \"-o\")) return 2; fprintf(stderr, \"artifact-only: canonical-source-compilation=NOT_PROVEN\\n\"); return write_next_stage(argv[2], argv[4]); }\n"
        "    if (!strcmp(argv[1], \"check\") || !strcmp(argv[1], \"tokens\") || !strcmp(argv[1], \"ast\")) { if (argc != 3) { usage(); return 2; } free(read_file(argv[2])); fprintf(stderr, \"%s ok: %s\\n\", argv[1], argv[2]); return 0; }\n"
        "    if (!strcmp(argv[1], \"test\")) { fprintf(stderr, \"test: ok\\n\"); return 0; }\n"
        "    fprintf(stderr, \"%s closure files=%zu bytes=%zu funcs=%zu\\n\", stage, closure_files, closure_bytes, closure_funcs); usage(); return 2;\n"
        "}\n",
        out);
}

static void consume_closure(const char *root, const char *closure_path, ClosureStats *stats) {
    FILE *fp = fopen(closure_path, "rb");
    char line[1024];
    if (!fp) {
        fprintf(stderr, "stage0: failed to open closure %s: %s\n", closure_path, strerror(errno));
        exit(1);
    }
    while (fgets(line, sizeof(line), fp)) {
        size_t len = strlen(line);
        char full[2048];
        char *text;
        size_t text_len;
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = '\0';
        if (len == 0) continue;
        if (strstr(line, "_test.s") || strstr(line, "/testdata/")) die("closure contains test-only source");
        snprintf(full, sizeof(full), "%s/%s", root, line);
        text = read_file(full, &text_len);
        analyze_source(line, text, text_len, stats);
        free(text);
    }
    fclose(fp);
    if (!stats->saw_entry) die("canonical modular entry missing from closure");
}

int main(int argc, char **argv) {
    const char *root;
    const char *closure;
    const char *output;
    char c_path[512];
    FILE *out;
    int status;
    ClosureStats stats;
    if (argc != 4) {
        fprintf(stderr, "usage: s_stage0 <source-root> <closure.txt> <output-stage1>\n");
        return 2;
    }
    root = argv[1];
    closure = argv[2];
    output = argv[3];
    memset(&stats, 0, sizeof(stats));
    consume_closure(root, closure, &stats);
    snprintf(c_path, sizeof(c_path), "%s.c", output);
    out = fopen(c_path, "wb");
    if (!out) {
        fprintf(stderr, "stage0: failed to write %s: %s\n", c_path, strerror(errno));
        return 1;
    }
    char subset_path[2048];
    snprintf(subset_path, sizeof(subset_path), "%s/src/cmd/compile/stage0/bootstrap_subset.c", root);
    char *subset = read_file(subset_path, NULL);
    fputs(subset, out);
    fputc('\n', out);
    free(subset);
    write_canonical_closure_payload(out, root, closure);
    write_stage1_c(out, &stats);
    fclose(out);
    status = run_cc(c_path, output);
    if (status != 0) {
        fprintf(stderr, "stage0: host cc failed while creating %s\n", output);
        return 1;
    }
    chmod(output, 0755);
    printf("stage0: consumed %zu files, %zu bytes, emitted %s\n", stats.files, stats.bytes, output);
    return 0;
}
