package compile.internal.syntax
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
    type_* int
    value* string
    line int
    col int
}

struct lexer {
    source* string
    pos int
    line int
    col int
    tokens* token
    token_count int
    token_capacity int
}

func lexer_new(string source*) lexer* {
    l := alloc(lexer)
    l.source = source
    l.pos = 0
    l.line = 1
    l.col = 1
    l.token_capacity = 1024
    l.tokens = alloc_array(token, l.token_capacity)
    l.token_count = 0
    return l
}

func lexer_current_char(l* lexer) int {
    if l.pos >= len(l.source) {
        return 0
    }
    return l.source[l.pos]
}

func lexer_peek_char(l* lexer, int offset) int {
    pos := l.pos + offset
    if pos >= len(l.source) {
        return 0
    }
    return l.source[pos]
}

func lexer_advance(l* lexer) {
    if l.pos < len(l.source) {
        if l.source[l.pos] == 10 {
            l.line = l.line + 1
            l.col = 1
        } else {
            l.col = l.col + 1
        }
        l.pos = l.pos + 1
    }
}

func lexer_skip_whitespace(l* lexer) {
    for {
        ch := lexer_current_char(l)
        if ch != 32 && ch != 9 {
            break
        }
        lexer_advance(l)
    }
}

func lexer_skip_line_comment(l* lexer) {
    for {
        ch := lexer_current_char(l)
        if ch == 10 || ch == 0 {
            break
        }
        lexer_advance(l)
    }
}

func lexer_skip_block_comment(l* lexer) {
    lexer_advance(l)
    lexer_advance(l)
    for {
        ch := lexer_current_char(l)
        if ch == 0 {
            break
        }
        if ch == 42 && lexer_peek_char(l, 1) == 47 {
            lexer_advance(l)
            lexer_advance(l)
            break
        }
        lexer_advance(l)
    }
}

func is_letter(int ch) int {
    return (ch >= 97 && ch <= 122) ||
           (ch >= 65 && ch <= 90) ||
           ch == 95
}

func is_digit(int ch) int {
    return ch >= 48 && ch <= 57
}

func is_alphanum(int ch) int {
    return is_letter(ch) || is_digit(ch) || ch == 95
}

func lexer_read_ident(l* lexer) token {
    start := l.pos
    start_col := l.col
    for {
        if !is_alphanum(lexer_current_char(l)) {
            break
        }
        lexer_advance(l)
    }
    length := l.pos - start
    value := substring(l.source, start, length)
    tok := alloc(token)
    tok.line = l.line
    tok.col = start_col
    tok.value = value
    tok.type_ = lexer_keyword_type(value)
    if tok.type_ == 0 {
        tok.type_ = 1
    }
    return *tok
}

func lexer_keyword_type(string s*) int {
    if s == nil {
        return 0
    }
    switch len(s) {
    case 2:
        if s == "if" {
            return 11
        }
        if s == "go" {
            return 23
        }
    case 3:
        if s == "for" {
            return 13
        }
        if s == "var" {
            return 8
        }
        if s == "map" {
            return 27
        }
    case 4:
        if s == "func" {
            return 5
        }
        if s == "else" {
            return 12
        }
        if s == "case" {
            return 17
        }
        if s == "type" {
            return 21
        }
        if s == "true" {
            return 37
        }
    case 5:
        if s == "const" {
            return 9
        }
        if s == "defer" {
            return 22
        }
        if s == "false" {
            return 38
        }
        if s == "iota" {
            return 40
        }
    case 6:
        if s == "return" {
            return 10
        }
        if s == "switch" {
            return 16
        }
        if s == "struct" {
            return 6
        }
        if s == "import" {
            return 19
        }
        if s == "select" {
            return 25
        }
        if s == "delete" {
            return 34
        }
    case 7:
        if s == "package" {
            return 20
        }
        if s == "default" {
            return 18
        }
    case 9:
        if s == "interface" {
            return 7
        }
    }
    return 0
}

func lexer_read_number(l* lexer) token {
    start := l.pos
    start_col := l.col
    if lexer_current_char(l) == 48 && lexer_peek_char(l, 1) == 120 {
        lexer_advance(l)
        lexer_advance(l)
        for {
            ch := lexer_current_char(l)
            if !is_digit(ch) &&
               !(ch >= 97 && ch <= 102) &&
               !(ch >= 65 && ch <= 70) {
                break
            }
            lexer_advance(l)
        }
    } else {
        for {
            if !is_digit(lexer_current_char(l)) {
                break
            }
            lexer_advance(l)
        }
        if lexer_current_char(l) == 46 && is_digit(lexer_peek_char(l, 1)) {
            lexer_advance(l)
            for {
                if !is_digit(lexer_current_char(l)) {
                    break
                }
                lexer_advance(l)
            }
        }
    }
    length := l.pos - start
    value := substring(l.source, start, length)
    tok := alloc(token)
    tok.line = l.line
    tok.col = start_col
    tok.type_ = 2
    tok.value = value
    return *tok
}

func lexer_read_string(l* lexer) token {
    start_col := l.col
    quote := lexer_current_char(l)
    lexer_advance(l)
    start := l.pos
    for {
        ch := lexer_current_char(l)
        if ch == 0 || ch == 10 {
            break
        }
        if ch == quote {
            break
        }
        if ch == 92 && lexer_peek_char(l, 1) == quote {
            lexer_advance(l)
            lexer_advance(l)
        } else {
            lexer_advance(l)
        }
    }
    length := l.pos - start
    value := substring(l.source, start, length)
    if lexer_current_char(l) == quote {
        lexer_advance(l)
    }
    tok := alloc(token)
    tok.line = l.line
    tok.col = start_col
    tok.type_ = 3
    tok.value = value
    return *tok
}

func lexer_add_token(l* lexer, tok* token) {
    if l.token_count >= l.token_capacity {
        new_capacity := l.token_capacity * 2
        new_tokens := alloc_array(token, new_capacity)
        copy_array(new_tokens, l.tokens, l.token_count)
        l.tokens = new_tokens
        l.token_capacity = new_capacity
    }
    l.tokens[l.token_count] = *tok
    l.token_count = l.token_count + 1
}

func lexer_tokenize(l* lexer) {
    for {
        lexer_skip_whitespace(l)
        ch := lexer_current_char(l)
        if ch == 0 {
            break
        }
        if ch == 47 {
            if lexer_peek_char(l, 1) == 47 {
                lexer_skip_line_comment(l)
                continue
            }
            if lexer_peek_char(l, 1) == 42 {
                lexer_skip_block_comment(l)
                continue
            }
        }
        if is_letter(ch) {
            tok := lexer_read_ident(l)
            lexer_add_token(l, &tok)
            continue
        }
        if is_digit(ch) {
            tok := lexer_read_number(l)
            lexer_add_token(l, &tok)
            continue
        }
        if ch == 34 || ch == 39 {
            tok := lexer_read_string(l)
            lexer_add_token(l, &tok)
            continue
        }
        tok_type := 0
        col := l.col
        switch ch {
        case 43:
            if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 52
            } else {
                tok_type = 41
            }
        case 45:
            if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 53
            } else {
                tok_type = 42
            }
        case 42:
            if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 54
            } else {
                tok_type = 43
            }
        case 47:
            if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 55
            } else {
                tok_type = 44
            }
        case 37:
            if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 56
            } else {
                tok_type = 45
            }
        case 38:
            if lexer_peek_char(l, 1) == 38 {
                lexer_advance(l)
                tok_type = 63
            } else if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 57
            } else if lexer_peek_char(l, 1) == 94 {
                lexer_advance(l)
                if lexer_peek_char(l, 1) == 61 {
                    lexer_advance(l)
                    tok_type = 62
                } else {
                    tok_type = 51
                }
            } else {
                tok_type = 46
            }
        case 124:
            if lexer_peek_char(l, 1) == 124 {
                lexer_advance(l)
                tok_type = 64
            } else if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 58
            } else {
                tok_type = 47
            }
        case 94:
            if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 59
            } else {
                tok_type = 48
            }
        case 60:
            if lexer_peek_char(l, 1) == 60 {
                lexer_advance(l)
                if lexer_peek_char(l, 1) == 61 {
                    lexer_advance(l)
                    tok_type = 60
                } else {
                    tok_type = 49
                }
            } else if lexer_peek_char(l, 1) == 45 {
                lexer_advance(l)
                tok_type = 74
            } else if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 69
            } else {
                tok_type = 68
            }
        case 62:
            if lexer_peek_char(l, 1) == 62 {
                lexer_advance(l)
                if lexer_peek_char(l, 1) == 61 {
                    lexer_advance(l)
                    tok_type = 61
                } else {
                    tok_type = 50
                }
            } else if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 71
            } else {
                tok_type = 70
            }
        case 33:
            if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 67
            } else {
                tok_type = 65
            }
        case 61:
            if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 66
            } else {
                tok_type = 72
            }
        case 58:
            if lexer_peek_char(l, 1) == 61 {
                lexer_advance(l)
                tok_type = 73
            } else {
                tok_type = 76
            }
        case 46:
            if lexer_peek_char(l, 1) == 46 && lexer_peek_char(l, 2) == 46 {
                lexer_advance(l)
                lexer_advance(l)
                tok_type = 75
            } else {
                tok_type = 77
            }
        case 44:
            tok_type = 78
        case 59:
            tok_type = 79
        case 40:
            tok_type = 80
        case 41:
            tok_type = 81
        case 123:
            tok_type = 82
        case 125:
            tok_type = 83
        case 91:
            tok_type = 84
        case 93:
            tok_type = 85
        case 10:
            tok_type = 86
        default:
            tok_type = 87
        }
        if tok_type > 0 {
            tok := alloc(token)
            tok.type_ = tok_type
            tok.line = l.line
            tok.col = col
            lexer_add_token(l, tok)
        }
        lexer_advance(l)
    }
    eof_tok := alloc(token)
    eof_tok.type_ = 0
    eof_tok.line = l.line
    eof_tok.col = l.col
    lexer_add_token(l, eof_tok)
}

func lexer_get_tokens(l* lexer) token* {
    return l.tokens
}

func lexer_get_token_count(l* lexer) int {
    return l.token_count
}
