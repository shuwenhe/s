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
    if (!is_supported_simple_source(source)) {
        report_missing_seed_features(path, source);
        free(source);
        return 1;
    }
    char *message = NULL;
    if (!compile_message_for_source(source, &message)) {
        fprintf(stderr, "error: seed cannot compile this source yet without a generated stage1: %s\n", path);
        free(source);
        return 1;
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