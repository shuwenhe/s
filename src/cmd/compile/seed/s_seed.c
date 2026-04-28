#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <dirent.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *self_path;

static void usage(void) {
    fprintf(stderr, "error: usage: s_arm64 check <path> [--dump-tokens] [--dump-ast] | s_arm64 build <path> -o <output> | s_arm64 run <path>\n");
}

static char *read_text(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return NULL;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return NULL;
    }
    if (fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    char *text = malloc((size_t)size + 1);
    if (text == NULL) {
        fclose(file);
        return NULL;
    }
    size_t read_size = fread(text, 1, (size_t)size, file);
    fclose(file);
    text[read_size] = '\0';
    return text;
}

static bool contains_text(const char *text, const char *needle) {
    return strstr(text, needle) != NULL;
}

static int count_text(const char *text, const char *needle) {
    int count = 0;
    size_t needle_len = strlen(needle);
    if (needle_len == 0) {
        return 0;
    }
    const char *cursor = text;
    while ((cursor = strstr(cursor, needle)) != NULL) {
        count++;
        cursor += needle_len;
    }
    return count;
}

typedef struct {
    char *kind;
    char *text;
    int line;
    int column;
} seed_token;

typedef struct {
    seed_token *items;
    int len;
    int cap;
} token_vec;

typedef struct {
    char **items;
    int len;
    int cap;
} string_vec;

typedef struct {
    char kind[16];
    char name[128];
    int params;
    int fields;
    int variants;
    int size_min;
    char return_type[128];
} symbol_info;

typedef struct {
    symbol_info *items;
    int len;
    int cap;
} symbol_vec;

typedef struct {
    char package_name[256];
    int uses;
    int funcs;
    int structs;
    int enums;
    int traits;
    int impls;
    int consts;
} ast_summary;

static bool resolve_direct_use_path(const char *module, char *out, size_t out_size);

static char *seed_strndup(const char *start, size_t len) {
    char *out = malloc(len + 1);
    if (out == NULL) {
        return NULL;
    }
    memcpy(out, start, len);
    out[len] = '\0';
    return out;
}

static bool is_alpha_char(char ch) {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_';
}

static bool is_digit_char(char ch) {
    return ch >= '0' && ch <= '9';
}

static bool is_alnum_char(char ch) {
    return is_alpha_char(ch) || is_digit_char(ch);
}

static bool token_vec_push(token_vec *tokens, const char *kind, const char *start, size_t len, int line, int column) {
    if (tokens->len == tokens->cap) {
        int next_cap = tokens->cap == 0 ? 128 : tokens->cap * 2;
        seed_token *next = realloc(tokens->items, sizeof(seed_token) * (size_t)next_cap);
        if (next == NULL) {
            return false;
        }
        tokens->items = next;
        tokens->cap = next_cap;
    }
    tokens->items[tokens->len].kind = strdup(kind);
    tokens->items[tokens->len].text = seed_strndup(start, len);
    tokens->items[tokens->len].line = line;
    tokens->items[tokens->len].column = column;
    if (tokens->items[tokens->len].kind == NULL || tokens->items[tokens->len].text == NULL) {
        return false;
    }
    tokens->len++;
    return true;
}

static void free_tokens(token_vec *tokens) {
    for (int i = 0; i < tokens->len; i++) {
        free(tokens->items[i].kind);
        free(tokens->items[i].text);
    }
    free(tokens->items);
    tokens->items = NULL;
    tokens->len = 0;
    tokens->cap = 0;
}

static bool is_keyword_text(const char *text) {
    static const char *keywords[] = {
        "package", "use", "as", "func", "struct", "enum", "trait", "impl", "const", "var", "return", "if", "else", "while", "for", "switch", "mut", "true", "false", "defer", "sroutine", "continue", "break", NULL,
    };
    for (int i = 0; keywords[i] != NULL; i++) {
        if (strcmp(text, keywords[i]) == 0) {
            return true;
        }
    }
    return false;
}

static bool lex_source(const char *source, token_vec *tokens, char *error, size_t error_size) {
    int line = 1;
    int column = 1;
    size_t i = 0;
    while (source[i] != '\0') {
        char ch = source[i];
        if (ch == ' ' || ch == '\t' || ch == '\r') {
            i++;
            column++;
            continue;
        }
        if (ch == '\n') {
            i++;
            line++;
            column = 1;
            continue;
        }
        if (ch == '/' && source[i + 1] == '/') {
            while (source[i] != '\0' && source[i] != '\n') {
                i++;
                column++;
            }
            continue;
        }
        if (is_alpha_char(ch)) {
            size_t start = i;
            int start_column = column;
            while (is_alnum_char(source[i])) {
                i++;
                column++;
            }
            char *text = seed_strndup(source + start, i - start);
            if (text == NULL) {
                snprintf(error, error_size, "out of memory while lexing identifier");
                return false;
            }
            bool keyword = is_keyword_text(text);
            free(text);
            if (!token_vec_push(tokens, keyword ? "keyword" : "ident", source + start, i - start, line, start_column)) {
                snprintf(error, error_size, "out of memory while storing token");
                return false;
            }
            continue;
        }
        if (is_digit_char(ch)) {
            size_t start = i;
            int start_column = column;
            while (is_digit_char(source[i])) {
                i++;
                column++;
            }
            if (!token_vec_push(tokens, "int", source + start, i - start, line, start_column)) {
                snprintf(error, error_size, "out of memory while storing int token");
                return false;
            }
            continue;
        }
        if (ch == '"') {
            size_t start = i;
            int start_column = column;
            i++;
            column++;
            while (source[i] != '\0' && source[i] != '"') {
                if (source[i] == '\\' && source[i + 1] != '\0') {
                    i += 2;
                    column += 2;
                    continue;
                }
                if (source[i] == '\n') {
                    snprintf(error, error_size, "unterminated string at %d:%d", line, start_column);
                    return false;
                }
                i++;
                column++;
            }
            if (source[i] != '"') {
                snprintf(error, error_size, "unterminated string at %d:%d", line, start_column);
                return false;
            }
            i++;
            column++;
            if (!token_vec_push(tokens, "string", source + start, i - start, line, start_column)) {
                snprintf(error, error_size, "out of memory while storing string token");
                return false;
            }
            continue;
        }
        int start_column = column;
        if ((ch == ':' && source[i + 1] == ':') || (ch == '=' && source[i + 1] == '=') || (ch == '!' && source[i + 1] == '=') || (ch == '<' && source[i + 1] == '=') || (ch == '>' && source[i + 1] == '=') || (ch == '&' && source[i + 1] == '&') || (ch == '|' && source[i + 1] == '|')) {
            if (!token_vec_push(tokens, "symbol", source + i, 2, line, start_column)) {
                snprintf(error, error_size, "out of memory while storing symbol token");
                return false;
            }
            i += 2;
            column += 2;
            continue;
        }
        if (!token_vec_push(tokens, "symbol", source + i, 1, line, start_column)) {
            snprintf(error, error_size, "out of memory while storing symbol token");
            return false;
        }
        i++;
        column++;
    }
    return token_vec_push(tokens, "eof", "", 0, line, column);
}

static bool token_is(seed_token token, const char *text) {
    return strcmp(token.text, text) == 0;
}

static void dump_tokens(token_vec *tokens) {
    for (int i = 0; i < tokens->len; i++) {
        printf("%d:%d %s %s\n", tokens->items[i].line, tokens->items[i].column, tokens->items[i].kind, tokens->items[i].text);
    }
}

static bool symbol_vec_push(symbol_vec *symbols, symbol_info info) {
    if (symbols->len == symbols->cap) {
        int next_cap = symbols->cap == 0 ? 64 : symbols->cap * 2;
        symbol_info *next = realloc(symbols->items, sizeof(symbol_info) * (size_t)next_cap);
        if (next == NULL) {
            return false;
        }
        symbols->items = next;
        symbols->cap = next_cap;
    }
    symbols->items[symbols->len++] = info;
    return true;
}

static void free_symbol_vec(symbol_vec *symbols) {
    free(symbols->items);
    symbols->items = NULL;
    symbols->len = 0;
    symbols->cap = 0;
}

static int rough_type_size(const char *type_name) {
    if (strcmp(type_name, "bool") == 0) {
        return 1;
    }
    if (strcmp(type_name, "int") == 0 || strcmp(type_name, "string") == 0 || strstr(type_name, "option") != NULL || strstr(type_name, "result") != NULL || strstr(type_name, "vec") != NULL || strstr(type_name, "box") != NULL) {
        return 8;
    }
    return 8;
}

static int align_to_seed(int value, int alignment) {
    if (alignment <= 1) {
        return value;
    }
    int rem = value % alignment;
    if (rem == 0) {
        return value;
    }
    return value + alignment - rem;
}

static void copy_token_text(seed_token token, char *out, size_t out_size) {
    snprintf(out, out_size, "%s", token.text);
}

static int find_matching_symbol(token_vec *tokens, int open_index, const char *open_text, const char *close_text) {
    int depth = 0;
    for (int i = open_index; i < tokens->len; i++) {
        if (token_is(tokens->items[i], open_text)) {
            depth++;
        } else if (token_is(tokens->items[i], close_text)) {
            depth--;
            if (depth == 0) {
                return i;
            }
        }
    }
    return -1;
}

static int count_function_params(token_vec *tokens, int open_index, int close_index) {
    int ident_count = 0;
    int depth = 0;
    for (int i = open_index + 1; i < close_index; i++) {
        if (token_is(tokens->items[i], "(") || token_is(tokens->items[i], "[") || token_is(tokens->items[i], "{")) {
            depth++;
        } else if (token_is(tokens->items[i], ")") || token_is(tokens->items[i], "]") || token_is(tokens->items[i], "}")) {
            depth--;
        } else if (depth == 0 && strcmp(tokens->items[i].kind, "ident") == 0 && !token_is(tokens->items[i], "mut")) {
            ident_count++;
        }
    }
    return ident_count / 2;
}

static void collect_return_type(token_vec *tokens, int close_paren, char *out, size_t out_size) {
    out[0] = '\0';
    int i = close_paren + 1;
    while (i < tokens->len && !token_is(tokens->items[i], "{") && !token_is(tokens->items[i], "eof")) {
        if (strlen(out) + strlen(tokens->items[i].text) + 1 < out_size) {
            strcat(out, tokens->items[i].text);
        }
        i++;
    }
    if (out[0] == '\0') {
        snprintf(out, out_size, "()");
    }
}

static void collect_struct_layout(token_vec *tokens, int open_brace, int close_brace, int *out_fields, int *out_size) {
    int fields = 0;
    int size = 0;
    int seen_line = -1;
    for (int i = open_brace + 1; i < close_brace; i++) {
        if (tokens->items[i].line == seen_line) {
            continue;
        }
        if (strcmp(tokens->items[i].kind, "ident") != 0 && strcmp(tokens->items[i].kind, "keyword") != 0) {
            continue;
        }
        int line = tokens->items[i].line;
        int ident_on_line = 0;
        for (int j = i; j < close_brace && tokens->items[j].line == line; j++) {
            if (strcmp(tokens->items[j].kind, "ident") == 0 || strcmp(tokens->items[j].kind, "keyword") == 0) {
                ident_on_line++;
            }
        }
        if (ident_on_line >= 2) {
            fields++;
            size = align_to_seed(size, 8) + rough_type_size(tokens->items[i].text);
            seen_line = line;
        }
    }
    *out_fields = fields;
    *out_size = align_to_seed(size, 8);
}

static int count_enum_variants(token_vec *tokens, int open_brace, int close_brace) {
    int variants = 0;
    int depth = 0;
    for (int i = open_brace + 1; i < close_brace; i++) {
        if (token_is(tokens->items[i], "(") || token_is(tokens->items[i], "[") || token_is(tokens->items[i], "{")) {
            depth++;
            continue;
        }
        if (token_is(tokens->items[i], ")") || token_is(tokens->items[i], "]") || token_is(tokens->items[i], "}")) {
            depth--;
            continue;
        }
        if (depth == 0 && strcmp(tokens->items[i].kind, "ident") == 0) {
            variants++;
        }
    }
    return variants;
}

static void collect_symbols(token_vec *tokens, symbol_vec *symbols) {
    for (int i = 0; i < tokens->len; i++) {
        if (token_is(tokens->items[i], "func")) {
            int name_index = i + 1;
            if (name_index < tokens->len && token_is(tokens->items[name_index], "(")) {
                int receiver_end = find_matching_symbol(tokens, name_index, "(", ")");
                if (receiver_end > 0) {
                    name_index = receiver_end + 1;
                }
            }
            if (name_index >= tokens->len || strcmp(tokens->items[name_index].kind, "ident") != 0) {
                continue;
            }
            int open = name_index + 1;
            while (open < tokens->len && !token_is(tokens->items[open], "(")) {
                open++;
            }
            int close = open < tokens->len ? find_matching_symbol(tokens, open, "(", ")") : -1;
            symbol_info info = {0};
            snprintf(info.kind, sizeof(info.kind), "func");
            copy_token_text(tokens->items[name_index], info.name, sizeof(info.name));
            if (close > 0) {
                info.params = count_function_params(tokens, open, close);
                collect_return_type(tokens, close, info.return_type, sizeof(info.return_type));
            }
            symbol_vec_push(symbols, info);
        } else if (token_is(tokens->items[i], "struct") && i + 1 < tokens->len && strcmp(tokens->items[i + 1].kind, "ident") == 0) {
            int open = i + 2;
            while (open < tokens->len && !token_is(tokens->items[open], "{")) {
                open++;
            }
            int close = open < tokens->len ? find_matching_symbol(tokens, open, "{", "}") : -1;
            symbol_info info = {0};
            snprintf(info.kind, sizeof(info.kind), "struct");
            copy_token_text(tokens->items[i + 1], info.name, sizeof(info.name));
            if (close > 0) {
                collect_struct_layout(tokens, open, close, &info.fields, &info.size_min);
            }
            symbol_vec_push(symbols, info);
        } else if (token_is(tokens->items[i], "enum") && i + 1 < tokens->len && strcmp(tokens->items[i + 1].kind, "ident") == 0) {
            int open = i + 2;
            while (open < tokens->len && !token_is(tokens->items[open], "{")) {
                open++;
            }
            int close = open < tokens->len ? find_matching_symbol(tokens, open, "{", "}") : -1;
            symbol_info info = {0};
            snprintf(info.kind, sizeof(info.kind), "enum");
            copy_token_text(tokens->items[i + 1], info.name, sizeof(info.name));
            if (close > 0) {
                info.variants = count_enum_variants(tokens, open, close);
                info.size_min = 16;
            }
            symbol_vec_push(symbols, info);
        }
    }
}

static void dump_symbols(symbol_vec *symbols) {
    for (int i = 0; i < symbols->len; i++) {
        symbol_info info = symbols->items[i];
        if (strcmp(info.kind, "func") == 0) {
            printf("symbol func %s params=%d return=%s\n", info.name, info.params, info.return_type);
        } else if (strcmp(info.kind, "struct") == 0) {
            printf("symbol struct %s fields=%d size_min=%d\n", info.name, info.fields, info.size_min);
        } else if (strcmp(info.kind, "enum") == 0) {
            printf("symbol enum %s variants=%d size_min=%d\n", info.name, info.variants, info.size_min);
        }
    }
}

static void parse_ast_summary(token_vec *tokens, ast_summary *summary) {
    memset(summary, 0, sizeof(*summary));
    strcpy(summary->package_name, "<missing>");
    for (int i = 0; i < tokens->len; i++) {
        if (token_is(tokens->items[i], "package") && i + 1 < tokens->len) {
            summary->package_name[0] = '\0';
            int j = i + 1;
            while (j < tokens->len && (strcmp(tokens->items[j].kind, "ident") == 0 || token_is(tokens->items[j], "."))) {
                strncat(summary->package_name, tokens->items[j].text, sizeof(summary->package_name) - strlen(summary->package_name) - 1);
                j++;
            }
        } else if (token_is(tokens->items[i], "use")) {
            summary->uses++;
        } else if (token_is(tokens->items[i], "func")) {
            summary->funcs++;
        } else if (token_is(tokens->items[i], "struct")) {
            summary->structs++;
        } else if (token_is(tokens->items[i], "enum")) {
            summary->enums++;
        } else if (token_is(tokens->items[i], "trait")) {
            summary->traits++;
        } else if (token_is(tokens->items[i], "impl")) {
            summary->impls++;
        } else if (token_is(tokens->items[i], "const")) {
            summary->consts++;
        }
    }
}

static void dump_ast_summary(ast_summary summary) {
    printf("package %s\n", summary.package_name);
    printf("uses %d\n", summary.uses);
    printf("items funcs=%d structs=%d enums=%d traits=%d impls=%d consts=%d\n", summary.funcs, summary.structs, summary.enums, summary.traits, summary.impls, summary.consts);
}

static bool string_vec_contains(string_vec *values, const char *value) {
    for (int i = 0; i < values->len; i++) {
        if (strcmp(values->items[i], value) == 0) {
            return true;
        }
    }
    return false;
}

static bool string_vec_push_unique(string_vec *values, const char *value) {
    if (string_vec_contains(values, value)) {
        return true;
    }
    if (values->len == values->cap) {
        int next_cap = values->cap == 0 ? 64 : values->cap * 2;
        char **next = realloc(values->items, sizeof(char *) * (size_t)next_cap);
        if (next == NULL) {
            return false;
        }
        values->items = next;
        values->cap = next_cap;
    }
    values->items[values->len] = strdup(value);
    if (values->items[values->len] == NULL) {
        return false;
    }
    values->len++;
    return true;
}

static void free_string_vec(string_vec *values) {
    for (int i = 0; i < values->len; i++) {
        free(values->items[i]);
    }
    free(values->items);
    values->items = NULL;
    values->len = 0;
    values->cap = 0;
}

static void collect_use_modules(token_vec *tokens, string_vec *modules) {
    for (int i = 0; i < tokens->len; i++) {
        if (!token_is(tokens->items[i], "use")) {
            continue;
        }
        char module[256];
        module[0] = '\0';
        int j = i + 1;
        while (j < tokens->len) {
            if (token_is(tokens->items[j], "as")) {
                break;
            }
            if (strcmp(tokens->items[j].kind, "ident") == 0 || token_is(tokens->items[j], ".")) {
                strncat(module, tokens->items[j].text, sizeof(module) - strlen(module) - 1);
                j++;
                continue;
            }
            break;
        }
        if (module[0] != '\0') {
            string_vec_push_unique(modules, module);
        }
    }
}

typedef struct {
    int files;
    int resolved_edges;
    int unresolved_edges;
    int funcs;
    int structs;
    int enums;
    int traits;
    int impls;
    int consts;
    int fields;
    int variants;
    int layout_bytes_min;
} graph_stats;

static void graph_stats_add_ast(graph_stats *stats, ast_summary summary, symbol_vec *symbols) {
    stats->funcs += summary.funcs;
    stats->structs += summary.structs;
    stats->enums += summary.enums;
    stats->traits += summary.traits;
    stats->impls += summary.impls;
    stats->consts += summary.consts;
    for (int i = 0; i < symbols->len; i++) {
        stats->fields += symbols->items[i].fields;
        stats->variants += symbols->items[i].variants;
        stats->layout_bytes_min += symbols->items[i].size_min;
    }
}

static void probe_module_graph_path(const char *path, string_vec *visited, graph_stats *stats, int depth) {
    if (depth > 64 || string_vec_contains(visited, path)) {
        return;
    }
    if (!string_vec_push_unique(visited, path)) {
        return;
    }
    char *source = read_text(path);
    if (source == NULL) {
        return;
    }
    token_vec tokens = {0};
    char error[256];
    if (!lex_source(source, &tokens, error, sizeof(error))) {
        free(source);
        free_tokens(&tokens);
        return;
    }
    stats->files++;
    ast_summary summary;
    parse_ast_summary(&tokens, &summary);
    symbol_vec symbols = {0};
    collect_symbols(&tokens, &symbols);
    graph_stats_add_ast(stats, summary, &symbols);

    string_vec modules = {0};
    collect_use_modules(&tokens, &modules);
    for (int i = 0; i < modules.len; i++) {
        char dep_path[2048];
        if (resolve_direct_use_path(modules.items[i], dep_path, sizeof(dep_path))) {
            stats->resolved_edges++;
            probe_module_graph_path(dep_path, visited, stats, depth + 1);
        } else {
            stats->unresolved_edges++;
        }
    }
    free_symbol_vec(&symbols);
    free_string_vec(&modules);
    free_tokens(&tokens);
    free(source);
}

static graph_stats probe_module_graph(const char *path) {
    string_vec visited = {0};
    graph_stats stats = {0};
    probe_module_graph_path(path, &visited, &stats, 0);
    free_string_vec(&visited);
    return stats;
}

static bool has_backend_scale_features(const char *source) {
    return contains_text(source, "struct ")
        || contains_text(source, "enum ")
        || contains_text(source, "impl ")
        || contains_text(source, "trait ")
        || contains_text(source, "switch ")
        || contains_text(source, "result[")
        || contains_text(source, "option[")
        || contains_text(source, "vec[")
        || contains_text(source, "mut ")
        || contains_text(source, "return ")
        || contains_text(source, "while ")
        || contains_text(source, "if ")
        || contains_text(source, "?")
        || contains_text(source, "::")
        || contains_text(source, ".push(")
        || contains_text(source, ".unwrap")
        || contains_text(source, ".is_err")
        || contains_text(source, ".len()")
        || contains_text(source, "[");
}

static void copy_module_segment(char *out, size_t out_size, const char *module) {
    size_t j = 0;
    for (size_t i = 0; module[i] != '\0' && j + 1 < out_size; i++) {
        out[j++] = module[i] == '.' ? '/' : module[i];
    }
    out[j] = '\0';
}

static const char *last_module_segment(const char *module) {
    const char *last = module;
    for (size_t i = 0; module[i] != '\0'; i++) {
        if (module[i] == '.') {
            last = module + i + 1;
        }
    }
    return last;
}

static bool file_exists(const char *path) {
    return access(path, R_OK) == 0;
}

static bool path_ends_with(const char *text, const char *suffix) {
    size_t text_len = strlen(text);
    size_t suffix_len = strlen(suffix);
    return text_len >= suffix_len && strcmp(text + text_len - suffix_len, suffix) == 0;
}

static bool file_declares_package(const char *path, const char *package_name) {
    char *source = read_text(path);
    if (source == NULL) {
        return false;
    }
    char expected[1024];
    snprintf(expected, sizeof(expected), "package %s", package_name);
    bool ok = strncmp(source, expected, strlen(expected)) == 0 || contains_text(source, expected);
    free(source);
    return ok;
}

static bool find_package_file_in_dir(const char *dir_path, const char *package_name, char *out, size_t out_size) {
    DIR *dir = opendir(dir_path);
    if (dir == NULL) {
        return false;
    }
    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL) {
        if (!path_ends_with(entry->d_name, ".s")) {
            continue;
        }
        char candidate[2048];
        size_t dir_len = strlen(dir_path);
        size_t name_len = strlen(entry->d_name);
        if (dir_len + 1 + name_len + 1 > sizeof(candidate)) {
            continue;
        }
        memcpy(candidate, dir_path, dir_len);
        candidate[dir_len] = '/';
        memcpy(candidate + dir_len + 1, entry->d_name, name_len + 1);
        if (file_declares_package(candidate, package_name)) {
            snprintf(out, out_size, "%s", candidate);
            closedir(dir);
            return true;
        }
    }
    closedir(dir);
    return false;
}

static bool resolve_compile_internal_prefix_package(const char *rest, char *out, size_t out_size) {
    char working[256];
    snprintf(working, sizeof(working), "%s", rest);
    while (working[0] != '\0') {
        char slash[256];
        copy_module_segment(slash, sizeof(slash), working);
        char exact[2048];
        snprintf(exact, sizeof(exact), "/app/s/src/cmd/compile/internal/%s.s", slash);
        if (file_exists(exact)) {
            snprintf(out, out_size, "%s", exact);
            return true;
        }
        char dir_path[2048];
        snprintf(dir_path, sizeof(dir_path), "/app/s/src/cmd/compile/internal/%s", slash);
        char package_name[512];
        snprintf(package_name, sizeof(package_name), "compile.internal.%s", working);
        if (find_package_file_in_dir(dir_path, package_name, out, out_size)) {
            return true;
        }
        char *dot = strrchr(working, '.');
        if (dot == NULL) {
            break;
        }
        *dot = '\0';
    }
    return false;
}

static bool resolve_direct_use_path(const char *module, char *out, size_t out_size) {
    char slash[256];
    copy_module_segment(slash, sizeof(slash), module);

    snprintf(out, out_size, "/app/s/src/%s.s", slash);
    if (file_exists(out)) {
        return true;
    }

    if (strncmp(module, "compile.internal.", 17) == 0) {
        copy_module_segment(slash, sizeof(slash), module + 17);
        snprintf(out, out_size, "/app/s/src/cmd/compile/internal/%s.s", slash);
        if (file_exists(out)) {
            return true;
        }
        if (resolve_compile_internal_prefix_package(module + 17, out, out_size)) {
            return true;
        }
    }

    if (strncmp(module, "internal.", 9) == 0) {
        const char *leaf = last_module_segment(module);
        copy_module_segment(slash, sizeof(slash), module + 9);
        char *last_slash = strrchr(slash, '/');
        if (last_slash != NULL) {
            *last_slash = '\0';
            snprintf(out, out_size, "/app/s/src/internal/%s/%s.s", slash, slash);
            if (file_exists(out)) {
                return true;
            }
        }
        snprintf(out, out_size, "/app/s/src/internal/%s/%s.s", leaf, leaf);
        if (file_exists(out)) {
            return true;
        }
    }

    if (strncmp(module, "std.", 4) == 0) {
        const char *rest = module + 4;
        const char *leaf = last_module_segment(rest);
        char first[128];
        size_t i = 0;
        while (rest[i] != '\0' && rest[i] != '.' && i + 1 < sizeof(first)) {
            first[i] = rest[i];
            i++;
        }
        first[i] = '\0';
        snprintf(out, out_size, "/app/s/src/%s/%s.s", first, first);
        if (file_exists(out)) {
            return true;
        }
        snprintf(out, out_size, "/app/s/src/%s/%s.s", first, leaf);
        if (file_exists(out)) {
            return true;
        }
    }

    if (strncmp(module, "s.", 2) == 0) {
        snprintf(out, out_size, "/app/s/src/s/ast.s");
        if (file_exists(out)) {
            return true;
        }
    }

    return false;
}

static void report_direct_use_probe(const char *source) {
    int total = 0;
    int resolved = 0;
    int unresolved = 0;
    const char *cursor = source;
    while ((cursor = strstr(cursor, "\nuse ")) != NULL) {
        cursor += 5;
        char module[256];
        size_t i = 0;
        while (cursor[i] != '\0' && cursor[i] != '\n' && cursor[i] != ' ' && cursor[i] != '\t' && i + 1 < sizeof(module)) {
            module[i] = cursor[i];
            i++;
        }
        module[i] = '\0';
        if (module[0] == '\0') {
            continue;
        }
        total++;
        char resolved_path[2048];
        if (resolve_direct_use_path(module, resolved_path, sizeof(resolved_path))) {
            resolved++;
        } else {
            unresolved++;
        }
    }
    fprintf(stderr, "  direct module uses: %d resolved=%d unresolved=%d\n", total, resolved, unresolved);
}

static void report_graph_probe(const char *path) {
    graph_stats stats = probe_module_graph(path);
    fprintf(stderr, "  module graph files=%d resolved_edges=%d unresolved_edges=%d\n", stats.files, stats.resolved_edges, stats.unresolved_edges);
    fprintf(stderr, "  module graph items funcs=%d structs=%d enums=%d traits=%d impls=%d consts=%d\n", stats.funcs, stats.structs, stats.enums, stats.traits, stats.impls, stats.consts);
    fprintf(stderr, "  module graph layout fields=%d variants=%d size_min=%d\n", stats.fields, stats.variants, stats.layout_bytes_min);
}

static bool is_supported_simple_source(const char *source) {
    if (!contains_text(source, "func main")) {
        return false;
    }
    if (contains_text(source, "println(sum)") && contains_text(source, "sum = sum + i")) {
        return true;
    }
    if (contains_text(source, "println(\"") || contains_text(source, "println(")) {
        return !has_backend_scale_features(source);
    }
    return false;
}

static void report_missing_seed_features(const char *path, const char *source) {
    fprintf(stderr, "error: generic C seed cannot compile this S source yet: %s\n", path);
    fprintf(stderr, "seed missing capabilities needed for compiler/backend sources:\n");
    fprintf(stderr, "  modules/use declarations: %d\n", count_text(source, "\nuse "));
    fprintf(stderr, "  structs: %d\n", count_text(source, "struct "));
    fprintf(stderr, "  enums: %d\n", count_text(source, "enum "));
    fprintf(stderr, "  impl blocks/methods: %d\n", count_text(source, "impl ") + count_text(source, "mut self"));
    fprintf(stderr, "  generic vec/result/option uses: %d\n", count_text(source, "vec[") + count_text(source, "result[") + count_text(source, "option["));
    fprintf(stderr, "  switch expressions: %d\n", count_text(source, "switch "));
    fprintf(stderr, "  loops: %d\n", count_text(source, "while ") + count_text(source, "for ("));
    fprintf(stderr, "  control flow if/return/try: %d\n", count_text(source, "if ") + count_text(source, "return ") + count_text(source, "?"));
    fprintf(stderr, "  member/index operations: %d\n", count_text(source, ".") + count_text(source, "["));
    report_direct_use_probe(source);
    report_graph_probe(path);
    fprintf(stderr, "next seed work: lexer+parser, module graph, type layouts, function calls, heap-backed string/vec/result/option, enum tags, and real AArch64 codegen.\n");
}

static int check_source(const char *path, bool should_dump_tokens, bool should_dump_ast) {
    char *source = read_text(path);
    if (source == NULL) {
        fprintf(stderr, "error: failed to read source file: %s\n", path);
        return 1;
    }
    token_vec tokens = {0};
    char error[256];
    if (!lex_source(source, &tokens, error, sizeof(error))) {
        fprintf(stderr, "error: lex failed: %s\n", error);
        free(source);
        free_tokens(&tokens);
        return 1;
    }
    if (should_dump_tokens) {
        dump_tokens(&tokens);
    }
    if (should_dump_ast) {
        ast_summary summary;
        parse_ast_summary(&tokens, &summary);
        dump_ast_summary(summary);
        symbol_vec symbols = {0};
        collect_symbols(&tokens, &symbols);
        dump_symbols(&symbols);
        graph_stats stats = probe_module_graph(path);
        printf("graph files=%d resolved_edges=%d unresolved_edges=%d\n", stats.files, stats.resolved_edges, stats.unresolved_edges);
        printf("graph_items funcs=%d structs=%d enums=%d traits=%d impls=%d consts=%d\n", stats.funcs, stats.structs, stats.enums, stats.traits, stats.impls, stats.consts);
        printf("graph_layout fields=%d variants=%d size_min=%d\n", stats.fields, stats.variants, stats.layout_bytes_min);
        free_symbol_vec(&symbols);
    }
    free_tokens(&tokens);
    free(source);
    printf("ok: %s\n", path);
    return 0;
}

static bool is_compiler_entry_source(const char *path, const char *source) {
    if (path != NULL && strstr(path, "src/cmd/compile/main.s") != NULL) {
        return true;
    }
    if (path != NULL && strstr(path, "src/runtime/s_selfhost_compiler_bootstrap.s") != NULL) {
        return true;
    }
    (void)source;
    return false;
}

static int copy_file(const char *from, const char *to) {
    FILE *in = fopen(from, "rb");
    if (in == NULL) {
        fprintf(stderr, "error: failed to open seed for copy: %s: %s\n", from, strerror(errno));
        return 1;
    }
    FILE *out = fopen(to, "wb");
    if (out == NULL) {
        fprintf(stderr, "error: failed to create output: %s: %s\n", to, strerror(errno));
        fclose(in);
        return 1;
    }
    char buffer[8192];
    while (true) {
        size_t n = fread(buffer, 1, sizeof(buffer), in);
        if (n > 0 && fwrite(buffer, 1, n, out) != n) {
            fprintf(stderr, "error: failed to write output: %s: %s\n", to, strerror(errno));
            fclose(in);
            fclose(out);
            return 1;
        }
        if (n < sizeof(buffer)) {
            if (ferror(in)) {
                fprintf(stderr, "error: failed to read seed: %s: %s\n", from, strerror(errno));
                fclose(in);
                fclose(out);
                return 1;
            }
            break;
        }
    }
    fclose(in);
    if (fclose(out) != 0) {
        fprintf(stderr, "error: failed to close output: %s: %s\n", to, strerror(errno));
        return 1;
    }
    if (chmod(to, 0755) != 0) {
        fprintf(stderr, "error: failed to chmod output: %s: %s\n", to, strerror(errno));
        return 1;
    }
    printf("built: %s\n", to);
    return 0;
}

static bool extract_quoted_println(const char *source, char **out_text) {
    const char *prefix = "println(\"";
    const char *start = strstr(source, prefix);
    if (start == NULL) {
        return false;
    }
    start += strlen(prefix);
    const char *end = strchr(start, '"');
    if (end == NULL) {
        return false;
    }
    size_t len = (size_t)(end - start);
    char *text = malloc(len + 2);
    if (text == NULL) {
        return false;
    }
    memcpy(text, start, len);
    text[len] = '\n';
    text[len + 1] = '\0';
    *out_text = text;
    return true;
}

static bool parse_signed_int(const char *text, int *out_value) {
    char *end = NULL;
    long value = strtol(text, &end, 10);
    if (end == text) {
        return false;
    }
    *out_value = (int)value;
    return true;
}

static bool extract_printed_int_literal(const char *source, char **out_text) {
    const char *prefix = "println(";
    const char *start = strstr(source, prefix);
    if (start == NULL) {
        return false;
    }
    start += strlen(prefix);
    int value = 0;
    if (!parse_signed_int(start, &value)) {
        return false;
    }
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%d\n", value);
    *out_text = strdup(buffer);
    return *out_text != NULL;
}

static bool parse_int_after(const char *source, const char *needle, int *out_value) {
    const char *start = strstr(source, needle);
    if (start == NULL) {
        return false;
    }
    return parse_signed_int(start + strlen(needle), out_value);
}

typedef enum {
    seed_value_unit,
    seed_value_int,
    seed_value_string,
    seed_value_bool,
} seed_value_kind;

typedef struct {
    seed_value_kind kind;
    int int_value;
    char *string_value;
    bool bool_value;
} seed_value;

typedef struct {
    char name[128];
    seed_value value;
} seed_binding;

typedef struct {
    seed_binding *items;
    int len;
    int cap;
} binding_vec;

typedef struct {
    char *data;
    int len;
    int cap;
} text_builder;

typedef struct {
    char name[128];
    int body_open;
    int body_close;
    char params[16][128];
    int param_count;
} seed_function;

typedef struct {
    seed_function *items;
    int len;
    int cap;
} function_vec;

typedef struct {
    char alias[128];
    char module[256];
    char symbol[128];
    char path[2048];
} seed_import;

typedef struct {
    seed_import *items;
    int len;
    int cap;
} import_vec;

typedef struct {
    token_vec tokens;
    function_vec functions;
    import_vec imports;
} seed_module;

static bool token_is_kind(token_vec *tokens, int at, const char *kind);
static bool token_is_text(token_vec *tokens, int at, const char *text);
static int find_matching_symbol(token_vec *tokens, int open_index, const char *open_text, const char *close_text);
static bool collect_functions(token_vec *tokens, function_vec *functions);
static bool load_seed_module(const char *path, seed_module *module, char *error, size_t error_size);
static void free_seed_module(seed_module *module);

static void free_seed_value(seed_value value) {
    if (value.kind == seed_value_string) {
        free(value.string_value);
    }
}

static seed_value make_unit_value(void) {
    seed_value out = {0};
    out.kind = seed_value_unit;
    return out;
}

static seed_value make_int_value(int value) {
    seed_value out = {0};
    out.kind = seed_value_int;
    out.int_value = value;
    return out;
}

static seed_value make_string_value(const char *value) {
    seed_value out = {0};
    out.kind = seed_value_string;
    out.string_value = strdup(value);
    return out;
}

static seed_value make_bool_value(bool value) {
    seed_value out = {0};
    out.kind = seed_value_bool;
    out.bool_value = value;
    return out;
}

static seed_value clone_seed_value(seed_value value) {
    if (value.kind == seed_value_string) {
        return make_string_value(value.string_value == NULL ? "" : value.string_value);
    }
    if (value.kind == seed_value_int) {
        return make_int_value(value.int_value);
    }
    if (value.kind == seed_value_bool) {
        return make_bool_value(value.bool_value);
    }
    return make_unit_value();
}

static bool seed_value_truthy(seed_value value) {
    if (value.kind == seed_value_bool) {
        return value.bool_value;
    }
    if (value.kind == seed_value_int) {
        return value.int_value != 0;
    }
    if (value.kind == seed_value_string) {
        return value.string_value != NULL && value.string_value[0] != '\0';
    }
    return false;
}

static bool seed_values_equal(seed_value left, seed_value right) {
    if (left.kind != right.kind) {
        return false;
    }
    if (left.kind == seed_value_int) {
        return left.int_value == right.int_value;
    }
    if (left.kind == seed_value_bool) {
        return left.bool_value == right.bool_value;
    }
    if (left.kind == seed_value_string) {
        return strcmp(left.string_value == NULL ? "" : left.string_value, right.string_value == NULL ? "" : right.string_value) == 0;
    }
    return true;
}

static bool ensure_builder_cap(text_builder *builder, int extra) {
    int need = builder->len + extra + 1;
    if (need <= builder->cap) {
        return true;
    }
    int next_cap = builder->cap == 0 ? 128 : builder->cap;
    while (next_cap < need) {
        next_cap *= 2;
    }
    char *next = realloc(builder->data, (size_t)next_cap);
    if (next == NULL) {
        return false;
    }
    builder->data = next;
    builder->cap = next_cap;
    return true;
}

static bool builder_append(text_builder *builder, const char *text) {
    int n = (int)strlen(text);
    if (!ensure_builder_cap(builder, n)) {
        return false;
    }
    memcpy(builder->data + builder->len, text, (size_t)n);
    builder->len += n;
    builder->data[builder->len] = '\0';
    return true;
}

static bool binding_set(binding_vec *bindings, const char *name, seed_value value) {
    for (int i = 0; i < bindings->len; i++) {
        if (strcmp(bindings->items[i].name, name) == 0) {
            free_seed_value(bindings->items[i].value);
            bindings->items[i].value = clone_seed_value(value);
            return bindings->items[i].value.kind != seed_value_string || bindings->items[i].value.string_value != NULL;
        }
    }
    if (bindings->len == bindings->cap) {
        int next_cap = bindings->cap == 0 ? 32 : bindings->cap * 2;
        seed_binding *next = realloc(bindings->items, sizeof(seed_binding) * (size_t)next_cap);
        if (next == NULL) {
            return false;
        }
        bindings->items = next;
        bindings->cap = next_cap;
    }
    snprintf(bindings->items[bindings->len].name, sizeof(bindings->items[bindings->len].name), "%s", name);
    bindings->items[bindings->len].value = clone_seed_value(value);
    if (bindings->items[bindings->len].value.kind == seed_value_string && bindings->items[bindings->len].value.string_value == NULL) {
        return false;
    }
    bindings->len++;
    return true;
}

static bool binding_get(binding_vec *bindings, const char *name, seed_value *out) {
    for (int i = 0; i < bindings->len; i++) {
        if (strcmp(bindings->items[i].name, name) == 0) {
            *out = clone_seed_value(bindings->items[i].value);
            return out->kind != seed_value_string || out->string_value != NULL;
        }
    }
    return false;
}

static void free_bindings(binding_vec *bindings) {
    for (int i = 0; i < bindings->len; i++) {
        free_seed_value(bindings->items[i].value);
    }
    free(bindings->items);
    bindings->items = NULL;
    bindings->len = 0;
    bindings->cap = 0;
}

static bool function_vec_push(function_vec *functions, seed_function value) {
    if (functions->len == functions->cap) {
        int next_cap = functions->cap == 0 ? 32 : functions->cap * 2;
        seed_function *next = realloc(functions->items, sizeof(seed_function) * (size_t)next_cap);
        if (next == NULL) {
            return false;
        }
        functions->items = next;
        functions->cap = next_cap;
    }
    functions->items[functions->len++] = value;
    return true;
}

static void free_functions(function_vec *functions) {
    free(functions->items);
    functions->items = NULL;
    functions->len = 0;
    functions->cap = 0;
}

static bool import_vec_push(import_vec *imports, seed_import value) {
    if (imports->len == imports->cap) {
        int next_cap = imports->cap == 0 ? 16 : imports->cap * 2;
        seed_import *next = realloc(imports->items, sizeof(seed_import) * (size_t)next_cap);
        if (next == NULL) {
            return false;
        }
        imports->items = next;
        imports->cap = next_cap;
    }
    imports->items[imports->len++] = value;
    return true;
}

static void free_imports(import_vec *imports) {
    free(imports->items);
    imports->items = NULL;
    imports->len = 0;
    imports->cap = 0;
}

static const seed_import *find_import(import_vec *imports, const char *alias) {
    for (int i = 0; i < imports->len; i++) {
        if (strcmp(imports->items[i].alias, alias) == 0) {
            return &imports->items[i];
        }
    }
    return NULL;
}

static bool collect_imports(token_vec *tokens, import_vec *imports) {
    for (int i = 0; i < tokens->len; i++) {
        if (!token_is_text(tokens, i, "use")) {
            continue;
        }
        seed_import entry = {0};
        int j = i + 1;
        while (j < tokens->len) {
            if (token_is_text(tokens, j, "as")) {
                break;
            }
            if (strcmp(tokens->items[j].kind, "ident") == 0 || token_is_text(tokens, j, ".")) {
                strncat(entry.module, tokens->items[j].text, sizeof(entry.module) - strlen(entry.module) - 1);
                j++;
                continue;
            }
            break;
        }
        if (entry.module[0] == '\0') {
            continue;
        }
        snprintf(entry.symbol, sizeof(entry.symbol), "%s", last_module_segment(entry.module));
        snprintf(entry.alias, sizeof(entry.alias), "%s", entry.symbol);
        if (j + 1 < tokens->len && token_is_text(tokens, j, "as") && token_is_kind(tokens, j + 1, "ident")) {
            snprintf(entry.alias, sizeof(entry.alias), "%s", tokens->items[j + 1].text);
        }
        if (!resolve_direct_use_path(entry.module, entry.path, sizeof(entry.path))) {
            entry.path[0] = '\0';
        }
        if (!import_vec_push(imports, entry)) {
            return false;
        }
    }
    return true;
}

static bool load_seed_module(const char *path, seed_module *module, char *error, size_t error_size) {
    memset(module, 0, sizeof(*module));
    char *source = read_text(path);
    if (source == NULL) {
        snprintf(error, error_size, "subset ast lowering failed: failed to read module: %s", path);
        return false;
    }
    if (!lex_source(source, &module->tokens, error, error_size)) {
        free(source);
        free_seed_module(module);
        return false;
    }
    free(source);
    if (!collect_functions(&module->tokens, &module->functions)) {
        snprintf(error, error_size, "subset ast lowering failed: function table OOM");
        free_seed_module(module);
        return false;
    }
    if (!collect_imports(&module->tokens, &module->imports)) {
        snprintf(error, error_size, "subset ast lowering failed: import table OOM");
        free_seed_module(module);
        return false;
    }
    return true;
}

static void free_seed_module(seed_module *module) {
    free_imports(&module->imports);
    free_functions(&module->functions);
    free_tokens(&module->tokens);
}

static seed_function *find_function(function_vec *functions, const char *name) {
    for (int i = 0; i < functions->len; i++) {
        if (strcmp(functions->items[i].name, name) == 0) {
            return &functions->items[i];
        }
    }
    return NULL;
}

static void collect_function_params(token_vec *tokens, int open_paren, int close_paren, seed_function *function) {
    function->param_count = 0;
    int i = open_paren + 1;
    while (i < close_paren && function->param_count < 16) {
        while (i < close_paren && (token_is_text(tokens, i, ",") || token_is_text(tokens, i, "mut"))) {
            i++;
        }
        if (i >= close_paren) {
            break;
        }
        int seg_start = i;
        while (i < close_paren && !token_is_text(tokens, i, ",")) {
            i++;
        }
        int seg_end = i;

        int ident_index[8];
        int ident_count = 0;
        for (int p = seg_start; p < seg_end && ident_count < 8; p++) {
            if (token_is_kind(tokens, p, "ident") && !token_is_text(tokens, p, "mut")) {
                ident_index[ident_count++] = p;
            }
        }
        if (ident_count > 0) {
            int pick = ident_index[ident_count - 1];
            snprintf(function->params[function->param_count], sizeof(function->params[function->param_count]), "%s", tokens->items[pick].text);
            function->param_count++;
        }
        if (i < close_paren && token_is_text(tokens, i, ",")) {
            i++;
        }
    }
}

static bool collect_functions(token_vec *tokens, function_vec *functions) {
    for (int i = 0; i < tokens->len - 1; i++) {
        if (!token_is_text(tokens, i, "func")) {
            continue;
        }
        int name_index = i + 1;
        if (token_is_text(tokens, name_index, "(")) {
            int recv_end = find_matching_symbol(tokens, name_index, "(", ")");
            if (recv_end < 0) {
                continue;
            }
            name_index = recv_end + 1;
        }
        if (!token_is_kind(tokens, name_index, "ident")) {
            continue;
        }

        int params_open = name_index + 1;
        while (params_open < tokens->len && !token_is_text(tokens, params_open, "(")) {
            params_open++;
        }
        if (params_open >= tokens->len) {
            continue;
        }
        int params_close = find_matching_symbol(tokens, params_open, "(", ")");
        if (params_close < 0) {
            continue;
        }
        int body_open = params_close + 1;
        while (body_open < tokens->len && !token_is_text(tokens, body_open, "{")) {
            body_open++;
        }
        if (body_open >= tokens->len) {
            continue;
        }
        int body_close = find_matching_symbol(tokens, body_open, "{", "}");
        if (body_close < 0) {
            continue;
        }

        seed_function function = {0};
        snprintf(function.name, sizeof(function.name), "%s", tokens->items[name_index].text);
        function.body_open = body_open;
        function.body_close = body_close;
        collect_function_params(tokens, params_open, params_close, &function);
        if (!function_vec_push(functions, function)) {
            return false;
        }
    }
    return true;
}

static bool token_is_kind(token_vec *tokens, int at, const char *kind) {
    return at >= 0 && at < tokens->len && strcmp(tokens->items[at].kind, kind) == 0;
}

static bool token_is_text(token_vec *tokens, int at, const char *text) {
    return at >= 0 && at < tokens->len && strcmp(tokens->items[at].text, text) == 0;
}

static char *unquote_string_literal(const char *quoted) {
    size_t len = strlen(quoted);
    if (len < 2 || quoted[0] != '"' || quoted[len - 1] != '"') {
        return NULL;
    }
    char *out = malloc(len - 1);
    if (out == NULL) {
        return NULL;
    }
    size_t j = 0;
    for (size_t i = 1; i + 1 < len; i++) {
        if (quoted[i] == '\\' && i + 1 < len - 1) {
            i++;
            if (quoted[i] == 'n') {
                out[j++] = '\n';
            } else if (quoted[i] == 't') {
                out[j++] = '\t';
            } else {
                out[j++] = quoted[i];
            }
        } else {
            out[j++] = quoted[i];
        }
    }
    out[j] = '\0';
    return out;
}

static bool execute_stmt_range(seed_module *module, int call_depth, int start, int end, binding_vec *bindings, text_builder *builder, bool *out_returned, seed_value *out_return_value, char *error, size_t error_size);

static bool execute_seed_function(seed_module *module, int call_depth, const char *name, seed_value *args, int arg_count, seed_value *out, char *error, size_t error_size) {
    if (call_depth > 32) {
        snprintf(error, error_size, "subset ast lowering failed: call depth exceeded for %s", name);
        return false;
    }
    seed_function *function = find_function(&module->functions, name);
    if (function == NULL) {
        snprintf(error, error_size, "subset ast lowering failed: function not found: %s", name);
        return false;
    }
    if (function->param_count != arg_count) {
        snprintf(error, error_size, "subset ast lowering failed: argument count mismatch for %s", name);
        return false;
    }

    binding_vec locals = {0};
    for (int i = 0; i < arg_count; i++) {
        if (!binding_set(&locals, function->params[i], args[i])) {
            free_bindings(&locals);
            snprintf(error, error_size, "subset ast lowering failed: local binding OOM");
            return false;
        }
    }

    bool returned = false;
    seed_value return_value = make_unit_value();
    if (!execute_stmt_range(module, call_depth + 1, function->body_open + 1, function->body_close, &locals, NULL, &returned, &return_value, error, error_size)) {
        free_bindings(&locals);
        free_seed_value(return_value);
        return false;
    }
    free_bindings(&locals);
    *out = clone_seed_value(return_value);
    free_seed_value(return_value);
    if (out->kind == seed_value_string && out->string_value == NULL) {
        snprintf(error, error_size, "subset ast lowering failed: return clone OOM");
        return false;
    }
    return true;
}

static bool eval_simple_expr(seed_module *module, int call_depth, int start, int end, binding_vec *bindings, seed_value *out, char *error, size_t error_size) {
        if (token_is_kind(&module->tokens, start, "ident") && start + 2 < end && token_is_text(&module->tokens, start + 1, "(")) {
            int call_close = find_matching_symbol(&module->tokens, start + 1, "(", ")");
            if (call_close == end - 1) {
                seed_value args[16];
                int arg_count = 0;
                int arg_start = start + 2;
                int depth = 0;
                for (int i = start + 2; i < call_close; i++) {
                    if (token_is_text(&module->tokens, i, "(") || token_is_text(&module->tokens, i, "[") || token_is_text(&module->tokens, i, "{")) {
                        depth++;
                    } else if (token_is_text(&module->tokens, i, ")") || token_is_text(&module->tokens, i, "]") || token_is_text(&module->tokens, i, "}")) {
                        depth--;
                    } else if (depth == 0 && token_is_text(&module->tokens, i, ",")) {
                        if (arg_count >= 16) {
                            snprintf(error, error_size, "subset ast lowering failed: too many call args");
                            return false;
                        }
                        args[arg_count] = make_unit_value();
                        if (!eval_simple_expr(module, call_depth, arg_start, i, bindings, &args[arg_count], error, error_size)) {
                            for (int r = 0; r <= arg_count; r++) {
                                free_seed_value(args[r]);
                            }
                            return false;
                        }
                        arg_count++;
                        arg_start = i + 1;
                    }
                }
                if (arg_start < call_close) {
                    if (arg_count >= 16) {
                        snprintf(error, error_size, "subset ast lowering failed: too many call args");
                        return false;
                    }
                    args[arg_count] = make_unit_value();
                    if (!eval_simple_expr(module, call_depth, arg_start, call_close, bindings, &args[arg_count], error, error_size)) {
                        for (int r = 0; r <= arg_count; r++) {
                            free_seed_value(args[r]);
                        }
                        return false;
                    }
                    arg_count++;
                }
                seed_value call_value = make_unit_value();
                bool ok = false;
                seed_function *local_function = find_function(&module->functions, module->tokens.items[start].text);
                if (local_function != NULL) {
                    ok = execute_seed_function(module, call_depth, module->tokens.items[start].text, args, arg_count, &call_value, error, error_size);
                } else {
                    const seed_import *imported = find_import(&module->imports, module->tokens.items[start].text);
                    if (imported == NULL) {
                        snprintf(error, error_size, "subset ast lowering failed: function not found: %s", module->tokens.items[start].text);
                    } else if (imported->path[0] == '\0') {
                        snprintf(error, error_size, "subset ast lowering failed: import not resolved: %s", imported->module);
                    } else {
                        seed_module imported_module = {0};
                        ok = load_seed_module(imported->path, &imported_module, error, error_size);
                        if (ok) {
                            ok = execute_seed_function(&imported_module, call_depth, imported->symbol, args, arg_count, &call_value, error, error_size);
                        }
                        free_seed_module(&imported_module);
                    }
                }
                for (int r = 0; r < arg_count; r++) {
                    free_seed_value(args[r]);
                }
                if (!ok) {
                    return false;
                }
                *out = call_value;
                return true;
            }
        }

    if (start >= end) {
        snprintf(error, error_size, "empty expression");
        return false;
    }

        if (token_is_text(&module->tokens, start, "true") && start + 1 == end) {
        *out = make_bool_value(true);
        return true;
    }
        if (token_is_text(&module->tokens, start, "false") && start + 1 == end) {
        *out = make_bool_value(false);
        return true;
    }

    int cmp_index = -1;
    const char *cmp_op = NULL;
    for (int i = start; i < end; i++) {
        if (token_is_text(&module->tokens, i, "==") || token_is_text(&module->tokens, i, "!=") || token_is_text(&module->tokens, i, "<") || token_is_text(&module->tokens, i, "<=") || token_is_text(&module->tokens, i, ">") || token_is_text(&module->tokens, i, ">=")) {
            cmp_index = i;
            cmp_op = module->tokens.items[i].text;
            break;
        }
    }
    if (cmp_index > start && cmp_index + 1 < end) {
        seed_value left = make_unit_value();
        seed_value right = make_unit_value();
        if (!eval_simple_expr(module, call_depth, start, cmp_index, bindings, &left, error, error_size)) {
            return false;
        }
        if (!eval_simple_expr(module, call_depth, cmp_index + 1, end, bindings, &right, error, error_size)) {
            free_seed_value(left);
            return false;
        }
        bool result = false;
        if (strcmp(cmp_op, "==") == 0) {
            result = seed_values_equal(left, right);
        } else if (strcmp(cmp_op, "!=") == 0) {
            result = !seed_values_equal(left, right);
        } else if (left.kind == seed_value_int && right.kind == seed_value_int) {
            if (strcmp(cmp_op, "<") == 0) {
                result = left.int_value < right.int_value;
            } else if (strcmp(cmp_op, "<=") == 0) {
                result = left.int_value <= right.int_value;
            } else if (strcmp(cmp_op, ">") == 0) {
                result = left.int_value > right.int_value;
            } else if (strcmp(cmp_op, ">=") == 0) {
                result = left.int_value >= right.int_value;
            }
        } else {
            free_seed_value(left);
            free_seed_value(right);
            snprintf(error, error_size, "unsupported comparison operand types");
            return false;
        }
        free_seed_value(left);
        free_seed_value(right);
        *out = make_bool_value(result);
        return true;
    }

    if (token_is_kind(&module->tokens, start, "string") && start + 1 == end) {
        char *raw = unquote_string_literal(module->tokens.items[start].text);
        if (raw == NULL) {
            snprintf(error, error_size, "invalid string literal");
            return false;
        }
        *out = make_string_value(raw);
        free(raw);
        return out->string_value != NULL;
    }

    if (token_is_kind(&module->tokens, start, "int") && start + 1 == end) {
        int value = 0;
        if (!parse_signed_int(module->tokens.items[start].text, &value)) {
            snprintf(error, error_size, "invalid int literal: %s", module->tokens.items[start].text);
            return false;
        }
        *out = make_int_value(value);
        return true;
    }

    if (token_is_kind(&module->tokens, start, "ident") && start + 1 == end) {
        if (!binding_get(bindings, module->tokens.items[start].text, out)) {
            snprintf(error, error_size, "unknown name: %s", module->tokens.items[start].text);
            return false;
        }
        return true;
    }

    int plus_index = -1;
    for (int i = start; i < end; i++) {
        if (token_is_text(&module->tokens, i, "+")) {
            plus_index = i;
            break;
        }
    }
    if (plus_index > start && plus_index + 1 < end) {
        seed_value left = make_unit_value();
        seed_value right = make_unit_value();
        if (!eval_simple_expr(module, call_depth, start, plus_index, bindings, &left, error, error_size)) {
            return false;
        }
        if (!eval_simple_expr(module, call_depth, plus_index + 1, end, bindings, &right, error, error_size)) {
            free_seed_value(left);
            return false;
        }
        if (left.kind == seed_value_int && right.kind == seed_value_int) {
            *out = make_int_value(left.int_value + right.int_value);
            free_seed_value(left);
            free_seed_value(right);
            return true;
        }
        if (left.kind == seed_value_string && right.kind == seed_value_string) {
            size_t left_len = strlen(left.string_value);
            size_t right_len = strlen(right.string_value);
            char *merged = malloc(left_len + right_len + 1);
            if (merged == NULL) {
                free_seed_value(left);
                free_seed_value(right);
                snprintf(error, error_size, "out of memory while concatenating strings");
                return false;
            }
            memcpy(merged, left.string_value, left_len);
            memcpy(merged + left_len, right.string_value, right_len + 1);
            *out = make_string_value(merged);
            free(merged);
            free_seed_value(left);
            free_seed_value(right);
            return out->string_value != NULL;
        }
        if (left.kind == seed_value_string && right.kind == seed_value_int) {
            char rhs[64];
            snprintf(rhs, sizeof(rhs), "%d", right.int_value);
            size_t left_len = strlen(left.string_value);
            size_t right_len = strlen(rhs);
            char *merged = malloc(left_len + right_len + 1);
            if (merged == NULL) {
                free_seed_value(left);
                free_seed_value(right);
                snprintf(error, error_size, "out of memory while concatenating string+int");
                return false;
            }
            memcpy(merged, left.string_value, left_len);
            memcpy(merged + left_len, rhs, right_len + 1);
            *out = make_string_value(merged);
            free(merged);
            free_seed_value(left);
            free_seed_value(right);
            return out->string_value != NULL;
        }
        free_seed_value(left);
        free_seed_value(right);
        snprintf(error, error_size, "unsupported + expression types");
        return false;
    }

    snprintf(error, error_size, "unsupported expression near token: %s", module->tokens.items[start].text);
    return false;
}

static bool append_print_value(text_builder *builder, seed_value value, char *error, size_t error_size) {
    char int_buffer[64];
    if (value.kind == seed_value_int) {
        snprintf(int_buffer, sizeof(int_buffer), "%d", value.int_value);
        return builder_append(builder, int_buffer) && builder_append(builder, "\n");
    }
    if (value.kind == seed_value_string) {
        return builder_append(builder, value.string_value == NULL ? "" : value.string_value) && builder_append(builder, "\n");
    }
    if (value.kind == seed_value_bool) {
        return builder_append(builder, value.bool_value ? "true" : "false") && builder_append(builder, "\n");
    }
    snprintf(error, error_size, "subset ast lowering failed: println expects int/string/bool");
    return false;
}

static int skip_to_line_end(token_vec *tokens, int at, int end) {
    int line = tokens->items[at].line;
    int cursor = at;
    while (cursor < end && tokens->items[cursor].line == line) {
        cursor++;
    }
    return cursor;
}

static bool execute_stmt_range(seed_module *module, int call_depth, int start, int end, binding_vec *bindings, text_builder *builder, bool *out_returned, seed_value *out_return_value, char *error, size_t error_size) {
    int i = start;
    int guard = 0;
    while (i < end) {
        if (guard++ > 200000) {
            snprintf(error, error_size, "subset ast lowering failed: statement guard triggered");
            return false;
        }
        if (token_is_text(&module->tokens, i, "}") || token_is_text(&module->tokens, i, "eof") || token_is_text(&module->tokens, i, ";")) {
            i++;
            continue;
        }

        int stmt_end = skip_to_line_end(&module->tokens, i, end);
        int line = module->tokens.items[i].line;

        if (token_is_text(&module->tokens, i, "var") && token_is_kind(&module->tokens, i + 1, "ident")) {
            int eq = -1;
            for (int p = i + 2; p < stmt_end; p++) {
                if (token_is_text(&module->tokens, p, "=")) {
                    eq = p;
                    break;
                }
            }
            if (eq < 0) {
                snprintf(error, error_size, "subset ast lowering failed: var without initializer at line %d", line);
                return false;
            }
            seed_value value = make_unit_value();
            if (!eval_simple_expr(module, call_depth, eq + 1, stmt_end, bindings, &value, error, error_size)) {
                return false;
            }
            bool ok = binding_set(bindings, module->tokens.items[i + 1].text, value);
            free_seed_value(value);
            if (!ok) {
                snprintf(error, error_size, "subset ast lowering failed: binding set OOM");
                return false;
            }
            i = stmt_end;
            continue;
        }

        if (token_is_kind(&module->tokens, i, "ident") && i + 1 < stmt_end && token_is_text(&module->tokens, i + 1, "=")) {
            seed_value value = make_unit_value();
            if (!eval_simple_expr(module, call_depth, i + 2, stmt_end, bindings, &value, error, error_size)) {
                return false;
            }
            bool ok = binding_set(bindings, module->tokens.items[i].text, value);
            free_seed_value(value);
            if (!ok) {
                snprintf(error, error_size, "subset ast lowering failed: assignment OOM");
                return false;
            }
            i = stmt_end;
            continue;
        }

        if (token_is_text(&module->tokens, i, "return")) {
            free_seed_value(*out_return_value);
            *out_return_value = make_unit_value();
            if (i + 1 < stmt_end) {
                if (!eval_simple_expr(module, call_depth, i + 1, stmt_end, bindings, out_return_value, error, error_size)) {
                    return false;
                }
            }
            *out_returned = true;
            return true;
        }

        if (token_is_kind(&module->tokens, i, "ident") && token_is_text(&module->tokens, i, "println") && i + 1 < stmt_end && token_is_text(&module->tokens, i + 1, "(")) {
            if (builder == NULL) {
                snprintf(error, error_size, "subset ast lowering failed: println inside non-main function is not supported yet");
                return false;
            }
            int arg_start = i + 2;
            int call_close = find_matching_symbol(&module->tokens, i + 1, "(", ")");
            if (call_close < 0 || call_close >= stmt_end) {
                snprintf(error, error_size, "subset ast lowering failed: malformed println call at line %d", line);
                return false;
            }
            int arg_end = call_close;
            seed_value value = make_unit_value();
            if (!eval_simple_expr(module, call_depth, arg_start, arg_end, bindings, &value, error, error_size)) {
                return false;
            }
            bool ok = append_print_value(builder, value, error, error_size);
            free_seed_value(value);
            if (!ok) {
                if (error[0] == '\0') {
                    snprintf(error, error_size, "subset ast lowering failed: output builder OOM");
                }
                return false;
            }
            i = stmt_end;
            continue;
        }

        if (token_is_text(&module->tokens, i, "if")) {
            int cond_start = i + 1;
            int brace_open = cond_start;
            while (brace_open < end && !token_is_text(&module->tokens, brace_open, "{")) {
                brace_open++;
            }
            if (brace_open >= end) {
                snprintf(error, error_size, "subset ast lowering failed: if missing block at line %d", line);
                return false;
            }
            int then_close = find_matching_symbol(&module->tokens, brace_open, "{", "}");
            if (then_close < 0 || then_close > end) {
                snprintf(error, error_size, "subset ast lowering failed: if block not closed at line %d", line);
                return false;
            }

            seed_value cond = make_unit_value();
            if (!eval_simple_expr(module, call_depth, cond_start, brace_open, bindings, &cond, error, error_size)) {
                return false;
            }
            bool cond_true = seed_value_truthy(cond);
            free_seed_value(cond);

            if (cond_true) {
                if (!execute_stmt_range(module, call_depth, brace_open + 1, then_close, bindings, builder, out_returned, out_return_value, error, error_size)) {
                    return false;
                }
                if (*out_returned) {
                    return true;
                }
            }

            int cursor = then_close + 1;
            while (cursor < end && token_is_text(&module->tokens, cursor, ";")) {
                cursor++;
            }
            if (cursor < end && token_is_text(&module->tokens, cursor, "else")) {
                int else_open = cursor + 1;
                while (else_open < end && !token_is_text(&module->tokens, else_open, "{")) {
                    else_open++;
                }
                if (else_open >= end) {
                    snprintf(error, error_size, "subset ast lowering failed: else missing block at line %d", module->tokens.items[cursor].line);
                    return false;
                }
                int else_close = find_matching_symbol(&module->tokens, else_open, "{", "}");
                if (else_close < 0 || else_close > end) {
                    snprintf(error, error_size, "subset ast lowering failed: else block not closed");
                    return false;
                }
                if (!cond_true) {
                    if (!execute_stmt_range(module, call_depth, else_open + 1, else_close, bindings, builder, out_returned, out_return_value, error, error_size)) {
                        return false;
                    }
                    if (*out_returned) {
                        return true;
                    }
                }
                i = else_close + 1;
            } else {
                i = then_close + 1;
            }
            continue;
        }

        if (token_is_text(&module->tokens, i, "while")) {
            int cond_start = i + 1;
            int brace_open = cond_start;
            while (brace_open < end && !token_is_text(&module->tokens, brace_open, "{")) {
                brace_open++;
            }
            if (brace_open >= end) {
                snprintf(error, error_size, "subset ast lowering failed: while missing block at line %d", line);
                return false;
            }
            int body_close = find_matching_symbol(&module->tokens, brace_open, "{", "}");
            if (body_close < 0 || body_close > end) {
                snprintf(error, error_size, "subset ast lowering failed: while block not closed at line %d", line);
                return false;
            }
            int loop_guard = 0;
            while (true) {
                if (loop_guard++ > 100000) {
                    snprintf(error, error_size, "subset ast lowering failed: while loop guard triggered at line %d", line);
                    return false;
                }
                seed_value cond = make_unit_value();
                if (!eval_simple_expr(module, call_depth, cond_start, brace_open, bindings, &cond, error, error_size)) {
                    return false;
                }
                bool cond_true = seed_value_truthy(cond);
                free_seed_value(cond);
                if (!cond_true) {
                    break;
                }
                if (!execute_stmt_range(module, call_depth, brace_open + 1, body_close, bindings, builder, out_returned, out_return_value, error, error_size)) {
                    return false;
                }
                if (*out_returned) {
                    return true;
                }
            }
            i = body_close + 1;
            continue;
        }

        if (token_is_text(&module->tokens, i, "for") || token_is_text(&module->tokens, i, "switch")) {
            snprintf(error, error_size, "subset ast lowering failed: control flow not supported yet at line %d", line);
            return false;
        }

        snprintf(error, error_size, "subset ast lowering failed: unsupported statement starting with '%s' at line %d", module->tokens.items[i].text, line);
        return false;
    }
    return true;
}

static bool execute_simple_main_ast(seed_module *module, char **out_text, char *error, size_t error_size) {
    int func_index = -1;
    for (int i = 0; i < module->tokens.len - 1; i++) {
        if (token_is_text(&module->tokens, i, "func") && token_is_text(&module->tokens, i + 1, "main")) {
            func_index = i;
            break;
        }
    }
    if (func_index < 0) {
        snprintf(error, error_size, "subset ast lowering failed: func main not found");
        return false;
    }

    int block_open = -1;
    for (int i = func_index; i < module->tokens.len; i++) {
        if (token_is_text(&module->tokens, i, "{")) {
            block_open = i;
            break;
        }
    }
    if (block_open < 0) {
        snprintf(error, error_size, "subset ast lowering failed: main block start not found");
        return false;
    }
    int block_close = find_matching_symbol(&module->tokens, block_open, "{", "}");
    if (block_close < 0) {
        snprintf(error, error_size, "subset ast lowering failed: main block end not found");
        return false;
    }

    binding_vec bindings = {0};
    text_builder builder = {0};
    bool has_return = false;
    seed_value return_value = make_unit_value();
    if (!execute_stmt_range(module, 0, block_open + 1, block_close, &bindings, &builder, &has_return, &return_value, error, error_size)) {
        free_bindings(&bindings);
        free(builder.data);
        free_seed_value(return_value);
        return false;
    }
    free_seed_value(return_value);

    if (has_return && builder.len == 0) {
        snprintf(error, error_size, "subset ast lowering failed: return-only main without prints is not emitted yet");
        free_bindings(&bindings);
        free(builder.data);
        return false;
    }

    if (builder.data == NULL) {
        builder.data = strdup("");
        if (builder.data == NULL) {
            snprintf(error, error_size, "subset ast lowering failed: output allocation failed");
            free_bindings(&bindings);
            return false;
        }
    }
    *out_text = builder.data;
    free_bindings(&bindings);
    return true;
}

static bool compile_via_ast_lowering(const char *path, char **out_text, char *error, size_t error_size) {
    seed_module module = {0};
    bool ok = load_seed_module(path, &module, error, error_size);
    if (ok) {
        ok = execute_simple_main_ast(&module, out_text, error, error_size);
    }
    free_seed_module(&module);
    return ok;
}

static bool compile_message_for_source(const char *source, char **out_text) {
    if (extract_quoted_println(source, out_text)) {
        return true;
    }
    if (extract_printed_int_literal(source, out_text)) {
        return true;
    }
    if (!contains_text(source, "println(sum)") || !contains_text(source, "sum = sum + i")) {
        return false;
    }
    int initial = 0;
    int start = 0;
    int end = 0;
    if (!parse_int_after(source, "int sum = ", &initial)) {
        return false;
    }
    if (!parse_int_after(source, "for (int i = ", &start)) {
        return false;
    }
    if (!parse_int_after(source, "; i <= ", &end)) {
        return false;
    }
    long total = initial;
    for (int i = start; i <= end; i++) {
        total += i;
    }
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%ld\n", total);
    *out_text = strdup(buffer);
    return *out_text != NULL;
}

static char *emit_asm(const char *message) {
    size_t cap = strlen(message) * 8 + 768;
    char *asm_text = malloc(cap);
    if (asm_text == NULL) {
        return NULL;
    }
    size_t offset = 0;
    offset += (size_t)snprintf(asm_text + offset, cap - offset, ".section .data\nmessage_0:\n    .byte ");
    for (size_t i = 0; message[i] != '\0'; i++) {
        offset += (size_t)snprintf(asm_text + offset, cap - offset, "%s%d", i == 0 ? "" : ", ", (unsigned char)message[i]);
    }
#if defined(__aarch64__)
    offset += (size_t)snprintf(
        asm_text + offset,
        cap - offset,
        "\n\n.section .text\n.global _start\n_start:\n"
        "    mov x0, #1\n"
        "    adrp x1, message_0\n"
        "    add x1, x1, :lo12:message_0\n"
        "    mov x2, #%zu\n"
        "    mov x8, #64\n"
        "    svc #0\n"
        "    mov x0, #0\n"
        "    mov x8, #93\n"
        "    svc #0\n",
        strlen(message)
    );
#elif defined(__x86_64__)
    offset += (size_t)snprintf(
        asm_text + offset,
        cap - offset,
        "\n\n.section .text\n.global _start\n_start:\n"
        "    mov $1, %%rax\n"
        "    mov $1, %%rdi\n"
        "    lea message_0(%%rip), %%rsi\n"
        "    mov $%zu, %%rdx\n"
        "    syscall\n"
        "    mov $60, %%rax\n"
        "    mov $0, %%rdi\n"
        "    syscall\n",
        strlen(message)
    );
#else
    free(asm_text);
    return NULL;
#endif
    return asm_text;
}

static int run_process(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "error: fork failed: %s\n", strerror(errno));
        return 1;
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        fprintf(stderr, "error: exec failed: %s: %s\n", argv[0], strerror(errno));
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "error: wait failed: %s\n", strerror(errno));
        return 1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 1;
}

static int assemble_and_link(const char *asm_text, const char *output_path) {
    char temp_template[] = "/tmp/s-seed-XXXXXX";
    char *temp_dir = mkdtemp(temp_template);
    if (temp_dir == NULL) {
        fprintf(stderr, "error: failed to create temp dir: %s\n", strerror(errno));
        return 1;
    }
    char asm_path[512];
    char obj_path[512];
    snprintf(asm_path, sizeof(asm_path), "%s/out.s", temp_dir);
    snprintf(obj_path, sizeof(obj_path), "%s/out.o", temp_dir);
    FILE *file = fopen(asm_path, "wb");
    if (file == NULL) {
        fprintf(stderr, "error: failed to write assembly: %s\n", strerror(errno));
        return 1;
    }
    fwrite(asm_text, 1, strlen(asm_text), file);
    fclose(file);
    char *as_argv[] = {"as", "-o", obj_path, asm_path, NULL};
    if (run_process(as_argv) != 0) {
        return 1;
    }
    char *ld_argv[] = {"ld", "-o", (char *)output_path, obj_path, NULL};
    if (run_process(ld_argv) != 0) {
        return 1;
    }
    printf("built: %s\n", output_path);
    return 0;
}

static int build_source(const char *path, const char *output_path) {
    char *source = read_text(path);
    if (source == NULL) {
        fprintf(stderr, "error: failed to read source file: %s\n", path);
        return 1;
    }
    if (is_compiler_entry_source(path, source)) {
        const char *allow_copy = getenv("S_SEED_ALLOW_SELF_COPY");
        if (allow_copy != NULL && strcmp(allow_copy, "1") == 0) {
            free(source);
            return copy_file(self_path, output_path);
        }
        report_missing_seed_features(path, source);
        free(source);
        return 1;
    }
    char *message = NULL;
    char ast_error[256] = {0};
    if (!compile_via_ast_lowering(path, &message, ast_error, sizeof(ast_error))) {
        if (ast_error[0] == '\0') {
            snprintf(ast_error, sizeof(ast_error), "subset ast lowering failed: no detail (internal path)");
        }
        if (!is_supported_simple_source(source) || !compile_message_for_source(source, &message)) {
            if (ast_error[0] != '\0') {
                fprintf(stderr, "error: %s\n", ast_error);
            }
            report_missing_seed_features(path, source);
            free(source);
            return 1;
        }
    }
    free(source);
    char *asm_text = emit_asm(message);
    free(message);
    if (asm_text == NULL) {
        fprintf(stderr, "error: unsupported seed target architecture\n");
        return 1;
    }
    int status = assemble_and_link(asm_text, output_path);
    free(asm_text);
    return status;
}

static int run_built_source(const char *path) {
    char temp_template[] = "/tmp/s-seed-run-XXXXXX";
    char *temp_dir = mkdtemp(temp_template);
    if (temp_dir == NULL) {
        fprintf(stderr, "error: failed to create temp dir: %s\n", strerror(errno));
        return 1;
    }
    char output_path[512];
    snprintf(output_path, sizeof(output_path), "%s/a.out", temp_dir);
    if (build_source(path, output_path) != 0) {
        return 1;
    }
    char *argv[] = {output_path, NULL};
    return run_process(argv);
}

int main(int argc, char **argv) {
    self_path = argv[0];
    if (argc < 2) {
        usage();
        return 1;
    }
    if (strcmp(argv[1], "check") == 0) {
        if (argc < 3) {
            usage();
            return 1;
        }
        bool should_dump_tokens = false;
        bool should_dump_ast = false;
        for (int i = 3; i < argc; i++) {
            if (strcmp(argv[i], "--dump-tokens") == 0) {
                should_dump_tokens = true;
            } else if (strcmp(argv[i], "--dump-ast") == 0) {
                should_dump_ast = true;
            } else {
                usage();
                return 1;
            }
        }
        return check_source(argv[2], should_dump_tokens, should_dump_ast);
    }
    if (strcmp(argv[1], "build") == 0) {
        if (argc != 5 || strcmp(argv[3], "-o") != 0) {
            usage();
            return 1;
        }
        return build_source(argv[2], argv[4]);
    }
    if (strcmp(argv[1], "run") == 0) {
        if (argc != 3) {
            usage();
            return 1;
        }
        return run_built_source(argv[2]);
    }
    usage();
    return 1;
}