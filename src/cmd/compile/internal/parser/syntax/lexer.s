package compile.internal.parser.syntax

enum token_type {
    tok_eof = 0,
    tok_ident = 1,
    tok_number = 2,
    tok_string = 3,
    tok_char = 4,
    tok_func = 5,
    tok_struct = 6,
    tok_interface = 7,
    tok_var = 8,
    tok_const = 9,
    tok_return = 10,
    tok_if = 11,
    tok_else = 12,
    tok_for = 13,
    tok_break = 14,
    tok_continue = 15,
    tok_switch = 16,
    tok_case = 17,
    tok_default = 18,
    tok_import = 19,
    tok_package = 20,
    tok_type = 21,
    tok_defer = 22,
    tok_go = 23,
    tok_chan = 24,
    tok_select = 25,
    tok_range = 26,
    tok_map = 27,
    tok_make = 28,
    tok_len = 29,
    tok_cap = 30,
    tok_append = 31,
    tok_copy = 32,
    tok_new = 33,
    tok_delete = 34,
    tok_panic = 35,
    tok_recover = 36,
    tok_true = 37,
    tok_false = 38,
    tok_nil = 39,
    tok_iota = 40,
    tok_plus = 41,
    tok_minus = 42,
    tok_star = 43,
    tok_slash = 44,
    tok_percent = 45,
    tok_ampersand = 46,
    tok_pipe = 47,
    tok_caret = 48,
    tok_lshift = 49,
    tok_rshift = 50,
    tok_ampersand_caret = 51,
    tok_plus_equal = 52,
    tok_minus_equal = 53,
    tok_star_equal = 54,
    tok_slash_equal = 55,
    tok_percent_equal = 56,
    tok_ampersand_equal = 57,
    tok_pipe_equal = 58,
    tok_caret_equal = 59,
    tok_lshift_equal = 60,
    tok_rshift_equal = 61,
    tok_ampersand_caret_equal = 62,
    tok_and = 63,
    tok_or = 64,
    tok_not = 65,
    tok_equal_equal = 66,
    tok_not_equal = 67,
    tok_less = 68,
    tok_less_equal = 69,
    tok_greater = 70,
    tok_greater_equal = 71,
    tok_equal = 72,
    tok_colon_equal = 73,
    tok_arrow = 74,
    tok_ellipsis = 75,
    tok_colon = 76,
    tok_dot = 77,
    tok_comma = 78,
    tok_semicolon = 79,
    tok_lparen = 80,
    tok_rparen = 81,
    tok_lbrace = 82,
    tok_rbrace = 83,
    tok_lbracket = 84,
    tok_rbracket = 85,
    tok_newline = 86,
    tok_error = 87,
}

struct token {
    int kind
    string value
    int line
    int col
}

struct syntax_lexer {
    string source
    int pos
    int line
    int col
    token[] tokens
    int token_count
}

// Dead code - lexer functions removed due to borrow rule violations
// The entire syntax package is not called from production code
extern "intrinsic" func __host_byte_at(string source, int index) int
extern "intrinsic" func __host_slice(string source, int start, int end) string
