package compile.internal.frontend

struct token {
    token_type: int
    value: string
    line: int
    column: int
}

struct lexer {
    source: string
    position: int
    read_position: int
    current_char: string
    line: int
    column: int
    start_column: int
}

const token_eof = 0
const token_error = 1

const token_ident = 10
const token_int = 11
const token_float = 12
const token_string = 13
const token_char = 14
const token_true = 15
const token_false = 16

const token_package = 20
const token_use = 21
const token_func = 22
const token_struct = 23
const token_enum = 24
const token_if = 25
const token_else = 26
const token_for = 27
const token_while = 28
const token_return = 29
const token_break = 30
const token_continue = 31
const token_switch = 32
const token_case = 33
const token_default = 34
const token_var = 35
const token_const = 36
const token_as = 37
const token_new = 38
const token_delete = 39

const token_plus = 40
const token_minus = 41
const token_star = 42
const token_slash = 43
const token_percent = 44
const token_eq = 45
const token_ne = 46
const token_lt = 47
const token_le = 48
const token_gt = 49
const token_ge = 50
const token_assign = 51
const token_colon_assign = 52
const token_plus_assign = 53
const token_minus_assign = 54
const token_star_assign = 55
const token_slash_assign = 56
const token_and = 57
const token_or = 58
const token_not = 59
const token_bit_and = 60
const token_bit_or = 61
const token_bit_xor = 62
const token_bit_not = 63
const token_lshift = 64
const token_rshift = 65
const token_lshift_assign = 66
const token_rshift_assign = 67
const token_and_assign = 68
const token_or_assign = 69
const token_xor_assign = 70

const token_lparen = 80
const token_rparen = 81
const token_lbrace = 82
const token_rbrace = 83
const token_lbracket = 84
const token_rbracket = 85
const token_comma = 86
const token_dot = 87
const token_colon = 88
const token_semicolon = 89
const token_arrow = 90
const token_question = 91

const token_newline = 99

func keyword_to_token(string kw) int {
    switch kw {
    case "package" : token_package
    case "use" : token_use
    case "func" : token_func
    case "struct" : token_struct
    case "enum" : token_enum
    case "if" : token_if
    case "else" : token_else
    case "for" : token_for
    case "while" : token_while
    case "return" : token_return
    case "break" : token_break
    case "continue" : token_continue
    case "switch" : token_switch
    case "case" : token_case
    case "default" : token_default
    case "var" : token_var
    case "const" : token_const
    case "true" : token_true
    case "false" : token_false
    case "as" : token_as
    case "new" : token_new
    case "delete" : token_delete
    default : token_ident
    }
}

func is_letter(string c) bool {
    return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_"
}

func is_digit(string c) bool {
    return c >= "0" && c <= "9"
}

func is_whitespace(string c) bool {
    return c == " " || c == "\t" || c == "\r"
}

func lexer_new(string source) lexer {
    lex := lexer {
        source: source, position: 0, read_position: 0,
        current_char: ' ', line: 1, column: 0, start_column: 0
    }
    lexer_read_char(lex*)
    lex
}

func lexer_read_char(lex* lexer) {
    if lex.read_position >= lex.source.len() {
        lex.current_char = '\0'
    } else {
        lex.current_char = lex.source[lex.read_position]
    }
    lex.position = lex.read_position
    lex.read_position = lex.read_position + 1

    if lex.current_char == '\n' {
        lex.line = lex.line + 1
        lex.column = 0
    } else {
        lex.column = lex.column + 1
    }
}

func lexer_peek_char(lex* lexer) string {
    if lex.read_position >= lex.source.len() {
        return '\0'
    } else {
        return lex.source[lex.read_position]
    }
}

func lexer_skip_whitespace(lex* lexer) {
    for is_whitespace(lex.current_char) {
        lexer_read_char(lex)
    }
}

func lexer_read_ident(lex* lexer) string {
    start := lex.position
    for is_letter(lex.current_char) || is_digit(lex.current_char) {
        lexer_read_char(lex)
    }
    lexer_slice(lex.source, start, lex.position)
}

func lexer_slice(string source, int start, int end) string {
    result := ""
    i := start
    for i < end {
        result = result + source[i]
        i = i + 1
    }
    result
}

func lexer_read_number(lex* lexer) (string, int) {
    start := lex.position
    has_dot := 0

    for is_digit(lex.current_char) || (lex.current_char == '.' && !has_dot) {
        if lex.current_char == '.' {
            has_dot = 1
        }
        lexer_read_char(lex)
    }

    num_str := lexer_slice(lex.source, start, lex.position)
    if has_dot {
        return num_str, token_float
    } else {
        return num_str, token_int
    }
}

func lexer_read_string(lex* lexer, string quote) string {
    lexer_read_char(lex)
    start := lex.position

    for lex.current_char != quote && lex.current_char != '\0' {
        if lex.current_char == '\\' {
            lexer_read_char(lex)
        }
        lexer_read_char(lex)
    }

    str := lexer_slice(lex.source, start, lex.position)
    if lex.current_char == quote {
        lexer_read_char(lex)
    }
    return str
}

func lexer_skip_line_comment(lex* lexer) {
    for lex.current_char != '\n' && lex.current_char != '\0' {
        lexer_read_char(lex)
    }
}

func lexer_skip_block_comment(lex* lexer) {
    lexer_read_char(lex)
    lexer_read_char(lex)

    for lex.current_char != '\0' {
        if lex.current_char == '*' && lexer_peek_char(lex) == '/' {
            lexer_read_char(lex)
            lexer_read_char(lex)
            break
        }
        lexer_read_char(lex)
    }
}

func lexer_next_token(lex* lexer) token {
    lexer_skip_whitespace(lex)

    lex.start_column = lex.column
    line := lex.line
    column := lex.column

    tok_type := token_eof
    tok_value := ""

    switch lex.current_char {
    case '\0' :
        tok_type = token_eof
        tok_value = ""
    case '\n' :
        tok_type = token_newline
        tok_value = "\n"
        lexer_read_char(lex)
    case '(' :
        tok_type = token_lparen
        tok_value = "("
        lexer_read_char(lex)
    case ')' :
        tok_type = token_rparen
        tok_value = ")"
        lexer_read_char(lex)
    case '{' :
        tok_type = token_lbrace
        tok_value = "{"
        lexer_read_char(lex)
    case '}' :
        tok_type = token_rbrace
        tok_value = "}"
        lexer_read_char(lex)
    case '[' :
        tok_type = token_lbracket
        tok_value = "["
        lexer_read_char(lex)
    case ']' :
        tok_type = token_rbracket
        tok_value = "]"
        lexer_read_char(lex)
    case ',' :
        tok_type = token_comma
        tok_value = ","
        lexer_read_char(lex)
    case '.' :
        tok_type = token_dot
        tok_value = "."
        lexer_read_char(lex)
    case ':' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_colon_assign
            tok_value = ":="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_colon
            tok_value = ":"
            lexer_read_char(lex)
        }
    case ';' :
        tok_type = token_semicolon
        tok_value = ";"
        lexer_read_char(lex)
    case '?' :
        tok_type = token_question
        tok_value = "?"
        lexer_read_char(lex)
    case '!' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_ne
            tok_value = "!="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_not
            tok_value = "!"
            lexer_read_char(lex)
        }
    case '=' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_eq
            tok_value = "=="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '>' {
            tok_type = token_arrow
            tok_value = "=>"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_assign
            tok_value = "="
            lexer_read_char(lex)
        }
    case '<' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_le
            tok_value = "<="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '<' {
            tok_type = token_lshift
            tok_value = "<<"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_lt
            tok_value = "<"
            lexer_read_char(lex)
        }
    case '>' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_ge
            tok_value = ">="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '>' {
            tok_type = token_rshift
            tok_value = ">>"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_gt
            tok_value = ">"
            lexer_read_char(lex)
        }
    case '+' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_plus_assign
            tok_value = "+="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_plus
            tok_value = "+"
            lexer_read_char(lex)
        }
    case '-' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_minus_assign
            tok_value = "-="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_minus
            tok_value = "-"
            lexer_read_char(lex)
        }
    case '*' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_star_assign
            tok_value = "*="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_star
            tok_value = "*"
            lexer_read_char(lex)
        }
    case '/' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_slash_assign
            tok_value = "/="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '/' {
            lexer_skip_line_comment(lex)
            return lexer_next_token(lex)
        } else if lexer_peek_char(lex) == '*' {
            lexer_skip_block_comment(lex)
            return lexer_next_token(lex)
        } else {
            tok_type = token_slash
            tok_value = "/"
            lexer_read_char(lex)
        }
    case '%' :
        tok_type = token_percent
        tok_value = "%"
        lexer_read_char(lex)
    case '&' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_and_assign
            tok_value = "&="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '&' {
            tok_type = token_and
            tok_value = "&&"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_bit_and
            tok_value = "&"
            lexer_read_char(lex)
        }
    case '|' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_or_assign
            tok_value = "|="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '|' {
            tok_type = token_or
            tok_value = "||"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_bit_or
            tok_value = "|"
            lexer_read_char(lex)
        }
    case '^' :
        if lexer_peek_char(lex) == '=' {
            tok_type = token_xor_assign
            tok_value = "^="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = token_bit_xor
            tok_value = "^"
            lexer_read_char(lex)
        }
    case '~' :
        tok_type = token_bit_not
        tok_value = "~"
        lexer_read_char(lex)
    case '"' :
        tok_type = token_string
        tok_value = lexer_read_string(lex, '"')
    case '\'' :
        tok_type = token_char
        tok_value = lexer_read_string(lex, '\'')
    default :
        if is_letter(lex.current_char) {
            ident := lexer_read_ident(lex)
            tok_type = keyword_to_token(ident)
            tok_value = ident
        } else if is_digit(lex.current_char) {
            tok_value, tok_type = lexer_read_number(lex)
        } else {
            tok_type = token_error
            tok_value = ""
            tok_value = tok_value + lex.current_char
            lexer_read_char(lex)
        }
    }

    token {
        token_type: tok_type, value: tok_value, line: line, column: column
    }
}

func token_type_name(int tok_type) string {
    switch tok_type {
    case token_eof : "EOF"
    case token_error : "ERROR"
    case token_ident : "IDENT"
    case token_int : "INT"
    case token_float : "FLOAT"
    case token_string : "STRING"
    case token_char : "CHAR"
    case token_true : "TRUE"
    case token_false : "FALSE"
    case token_package : "PACKAGE"
    case token_use : "USE"
    case token_func : "FUNC"
    case token_struct : "STRUCT"
    case token_enum : "ENUM"
    case token_if : "IF"
    case token_else : "ELSE"
    case token_for : "FOR"
    case token_while : "WHILE"
    case token_return : "RETURN"
    case token_break : "BREAK"
    case token_continue : "CONTINUE"
    case token_switch : "SWITCH"
    case token_case : "CASE"
    case token_default : "DEFAULT"
    case token_var : "VAR"
    case token_const : "CONST"
    case token_as : "AS"
    case token_new : "NEW"
    case token_delete : "DELETE"
    case token_plus : "PLUS"
    case token_minus : "MINUS"
    case token_star : "STAR"
    case token_slash : "SLASH"
    case token_percent : "PERCENT"
    case token_eq : "EQ"
    case token_ne : "NE"
    case token_lt : "LT"
    case token_le : "LE"
    case token_gt : "GT"
    case token_ge : "GE"
    case token_assign : "ASSIGN"
    case token_colon_assign : "COLON_ASSIGN"
    case token_plus_assign : "PLUS_ASSIGN"
    case token_minus_assign : "MINUS_ASSIGN"
    case token_star_assign : "STAR_ASSIGN"
    case token_slash_assign : "SLASH_ASSIGN"
    case token_and : "AND"
    case token_or : "OR"
    case token_not : "NOT"
    case token_bit_and : "BIT_AND"
    case token_bit_or : "BIT_OR"
    case token_bit_xor : "BIT_XOR"
    case token_bit_not : "BIT_NOT"
    case token_lshift : "LSHIFT"
    case token_rshift : "RSHIFT"
    case token_lshift_assign : "LSHIFT_ASSIGN"
    case token_rshift_assign : "RSHIFT_ASSIGN"
    case token_and_assign : "AND_ASSIGN"
    case token_or_assign : "OR_ASSIGN"
    case token_xor_assign : "XOR_ASSIGN"
    case token_lparen : "LPAREN"
    case token_rparen : "RPAREN"
    case token_lbrace : "LBRACE"
    case token_rbrace : "RBRACE"
    case token_lbracket : "LBRACKET"
    case token_rbracket : "RBRACKET"
    case token_comma : "COMMA"
    case token_dot : "DOT"
    case token_colon : "COLON"
    case token_semicolon : "SEMICOLON"
    case token_arrow : "ARROW"
    case token_question : "QUESTION"
    case token_newline : "NEWLINE"
    default : "UNKNOWN"
    }
}
