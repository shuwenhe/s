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

const TOKEN_EOF = 0
const TOKEN_ERROR = 1

const TOKEN_IDENT = 10
const TOKEN_INT = 11
const TOKEN_FLOAT = 12
const TOKEN_STRING = 13
const TOKEN_CHAR = 14
const TOKEN_TRUE = 15
const TOKEN_FALSE = 16

const TOKEN_PACKAGE = 20
const TOKEN_USE = 21
const TOKEN_FUNC = 22
const TOKEN_STRUCT = 23
const TOKEN_ENUM = 24
const TOKEN_IF = 25
const TOKEN_ELSE = 26
const TOKEN_FOR = 27
const TOKEN_WHILE = 28
const TOKEN_RETURN = 29
const TOKEN_BREAK = 30
const TOKEN_CONTINUE = 31
const TOKEN_SWITCH = 32
const TOKEN_CASE = 33
const TOKEN_DEFAULT = 34
const TOKEN_VAR = 35
const TOKEN_CONST = 36
const TOKEN_AS = 37
const TOKEN_NEW = 38
const TOKEN_DELETE = 39

const TOKEN_PLUS = 40
const TOKEN_MINUS = 41
const TOKEN_STAR = 42
const TOKEN_SLASH = 43
const TOKEN_PERCENT = 44
const TOKEN_EQ = 45
const TOKEN_NE = 46
const TOKEN_LT = 47
const TOKEN_LE = 48
const TOKEN_GT = 49
const TOKEN_GE = 50
const TOKEN_ASSIGN = 51
const TOKEN_COLON_ASSIGN = 52
const TOKEN_PLUS_ASSIGN = 53
const TOKEN_MINUS_ASSIGN = 54
const TOKEN_STAR_ASSIGN = 55
const TOKEN_SLASH_ASSIGN = 56
const TOKEN_AND = 57
const TOKEN_OR = 58
const TOKEN_NOT = 59
const TOKEN_BIT_AND = 60
const TOKEN_BIT_OR = 61
const TOKEN_BIT_XOR = 62
const TOKEN_BIT_NOT = 63
const TOKEN_LSHIFT = 64
const TOKEN_RSHIFT = 65
const TOKEN_LSHIFT_ASSIGN = 66
const TOKEN_RSHIFT_ASSIGN = 67
const TOKEN_AND_ASSIGN = 68
const TOKEN_OR_ASSIGN = 69
const TOKEN_XOR_ASSIGN = 70

const TOKEN_LPAREN = 80
const TOKEN_RPAREN = 81
const TOKEN_LBRACE = 82
const TOKEN_RBRACE = 83
const TOKEN_LBRACKET = 84
const TOKEN_RBRACKET = 85
const TOKEN_COMMA = 86
const TOKEN_DOT = 87
const TOKEN_COLON = 88
const TOKEN_SEMICOLON = 89
const TOKEN_ARROW = 90
const TOKEN_QUESTION = 91

const TOKEN_NEWLINE = 99

func keyword_to_token(string kw) int {
    switch kw {
    case "package" : TOKEN_PACKAGE
    case "use" : TOKEN_USE
    case "func" : TOKEN_FUNC
    case "struct" : TOKEN_STRUCT
    case "enum" : TOKEN_ENUM
    case "if" : TOKEN_IF
    case "else" : TOKEN_ELSE
    case "for" : TOKEN_FOR
    case "while" : TOKEN_WHILE
    case "return" : TOKEN_RETURN
    case "break" : TOKEN_BREAK
    case "continue" : TOKEN_CONTINUE
    case "switch" : TOKEN_SWITCH
    case "case" : TOKEN_CASE
    case "default" : TOKEN_DEFAULT
    case "var" : TOKEN_VAR
    case "const" : TOKEN_CONST
    case "true" : TOKEN_TRUE
    case "false" : TOKEN_FALSE
    case "as" : TOKEN_AS
    case "new" : TOKEN_NEW
    case "delete" : TOKEN_DELETE
    default : TOKEN_IDENT
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
        source: source,
        position: 0,
        read_position: 0,
        current_char: ' ',
        line: 1,
        column: 0,
        start_column: 0
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
        '\0'
    } else {
        lex.source[lex.read_position]
    }
}

func lexer_skip_whitespace(lex* lexer) {
    while is_whitespace(lex.current_char) {
        lexer_read_char(lex)
    }
}

func lexer_read_ident(lex* lexer) string {
    start := lex.position
    while is_letter(lex.current_char) || is_digit(lex.current_char) {
        lexer_read_char(lex)
    }
    lexer_slice(lex.source, start, lex.position)
}

func lexer_slice(string source, int start, int end) string {
    result := ""
    i := start
    while i < end {
        result = result + source[i]
        i = i + 1
    }
    result
}

func lexer_read_number(lex* lexer) (string, int) {
    start := lex.position
    has_dot := 0
    
    while is_digit(lex.current_char) || (lex.current_char == '.' && !has_dot) {
        if lex.current_char == '.' {
            has_dot = 1
        }
        lexer_read_char(lex)
    }
    
    num_str := lexer_slice(lex.source, start, lex.position)
    if has_dot {
        num_str, TOKEN_FLOAT
    } else {
        num_str, TOKEN_INT
    }
}

func lexer_read_string(lex* lexer, string quote) string {
    lexer_read_char(lex)
    start := lex.position
    
    while lex.current_char != quote && lex.current_char != '\0' {
        if lex.current_char == '\\' {
            lexer_read_char(lex)
        }
        lexer_read_char(lex)
    }
    
    str := lexer_slice(lex.source, start, lex.position)
    if lex.current_char == quote {
        lexer_read_char(lex)
    }
    str
}

func lexer_skip_line_comment(lex* lexer) {
    while lex.current_char != '\n' && lex.current_char != '\0' {
        lexer_read_char(lex)
    }
}

func lexer_skip_block_comment(lex* lexer) {
    lexer_read_char(lex)
    lexer_read_char(lex)
    
    while lex.current_char != '\0' {
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
    
    tok_type := TOKEN_EOF
    tok_value := ""
    
    switch lex.current_char {
    case '\0' :
        tok_type = TOKEN_EOF
        tok_value = ""
    case '\n' :
        tok_type = TOKEN_NEWLINE
        tok_value = "\n"
        lexer_read_char(lex)
    case '(' :
        tok_type = TOKEN_LPAREN
        tok_value = "("
        lexer_read_char(lex)
    case ')' :
        tok_type = TOKEN_RPAREN
        tok_value = ")"
        lexer_read_char(lex)
    case '{' :
        tok_type = TOKEN_LBRACE
        tok_value = "{"
        lexer_read_char(lex)
    case '}' :
        tok_type = TOKEN_RBRACE
        tok_value = "}"
        lexer_read_char(lex)
    case '[' :
        tok_type = TOKEN_LBRACKET
        tok_value = "["
        lexer_read_char(lex)
    case ']' :
        tok_type = TOKEN_RBRACKET
        tok_value = "]"
        lexer_read_char(lex)
    case ',' :
        tok_type = TOKEN_COMMA
        tok_value = ","
        lexer_read_char(lex)
    case '.' :
        tok_type = TOKEN_DOT
        tok_value = "."
        lexer_read_char(lex)
    case ':' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_COLON_ASSIGN
            tok_value = ":="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_COLON
            tok_value = ":"
            lexer_read_char(lex)
        }
    case ';' :
        tok_type = TOKEN_SEMICOLON
        tok_value = ";"
        lexer_read_char(lex)
    case '?' :
        tok_type = TOKEN_QUESTION
        tok_value = "?"
        lexer_read_char(lex)
    case '!' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_NE
            tok_value = "!="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_NOT
            tok_value = "!"
            lexer_read_char(lex)
        }
    case '=' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_EQ
            tok_value = "=="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '>' {
            tok_type = TOKEN_ARROW
            tok_value = "=>"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_ASSIGN
            tok_value = "="
            lexer_read_char(lex)
        }
    case '<' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_LE
            tok_value = "<="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '<' {
            tok_type = TOKEN_LSHIFT
            tok_value = "<<"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_LT
            tok_value = "<"
            lexer_read_char(lex)
        }
    case '>' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_GE
            tok_value = ">="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '>' {
            tok_type = TOKEN_RSHIFT
            tok_value = ">>"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_GT
            tok_value = ">"
            lexer_read_char(lex)
        }
    case '+' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_PLUS_ASSIGN
            tok_value = "+="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_PLUS
            tok_value = "+"
            lexer_read_char(lex)
        }
    case '-' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_MINUS_ASSIGN
            tok_value = "-="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_MINUS
            tok_value = "-"
            lexer_read_char(lex)
        }
    case '*' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_STAR_ASSIGN
            tok_value = "*="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_STAR
            tok_value = "*"
            lexer_read_char(lex)
        }
    case '/' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_SLASH_ASSIGN
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
            tok_type = TOKEN_SLASH
            tok_value = "/"
            lexer_read_char(lex)
        }
    case '%' :
        tok_type = TOKEN_PERCENT
        tok_value = "%"
        lexer_read_char(lex)
    case '&' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_AND_ASSIGN
            tok_value = "&="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '&' {
            tok_type = TOKEN_AND
            tok_value = "&&"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_BIT_AND
            tok_value = "&"
            lexer_read_char(lex)
        }
    case '|' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_OR_ASSIGN
            tok_value = "|="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else if lexer_peek_char(lex) == '|' {
            tok_type = TOKEN_OR
            tok_value = "||"
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_BIT_OR
            tok_value = "|"
            lexer_read_char(lex)
        }
    case '^' :
        if lexer_peek_char(lex) == '=' {
            tok_type = TOKEN_XOR_ASSIGN
            tok_value = "^="
            lexer_read_char(lex)
            lexer_read_char(lex)
        } else {
            tok_type = TOKEN_BIT_XOR
            tok_value = "^"
            lexer_read_char(lex)
        }
    case '~' :
        tok_type = TOKEN_BIT_NOT
        tok_value = "~"
        lexer_read_char(lex)
    case '"' :
        tok_type = TOKEN_STRING
        tok_value = lexer_read_string(lex, '"')
    case '\'' :
        tok_type = TOKEN_CHAR
        tok_value = lexer_read_string(lex, '\'')
    default :
        if is_letter(lex.current_char) {
            ident := lexer_read_ident(lex)
            tok_type = keyword_to_token(ident)
            tok_value = ident
        } else if is_digit(lex.current_char) {
            tok_value, tok_type = lexer_read_number(lex)
        } else {
            tok_type = TOKEN_ERROR
            tok_value = ""
            tok_value = tok_value + lex.current_char
            lexer_read_char(lex)
        }
    }
    
    token {
        token_type: tok_type,
        value: tok_value,
        line: line,
        column: column
    }
}

func token_type_name(int tok_type) string {
    switch tok_type {
    case TOKEN_EOF : "EOF"
    case TOKEN_ERROR : "ERROR"
    case TOKEN_IDENT : "IDENT"
    case TOKEN_INT : "INT"
    case TOKEN_FLOAT : "FLOAT"
    case TOKEN_STRING : "STRING"
    case TOKEN_CHAR : "CHAR"
    case TOKEN_TRUE : "TRUE"
    case TOKEN_FALSE : "FALSE"
    case TOKEN_PACKAGE : "PACKAGE"
    case TOKEN_USE : "USE"
    case TOKEN_FUNC : "FUNC"
    case TOKEN_STRUCT : "STRUCT"
    case TOKEN_ENUM : "ENUM"
    case TOKEN_IF : "IF"
    case TOKEN_ELSE : "ELSE"
    case TOKEN_FOR : "FOR"
    case TOKEN_WHILE : "WHILE"
    case TOKEN_RETURN : "RETURN"
    case TOKEN_BREAK : "BREAK"
    case TOKEN_CONTINUE : "CONTINUE"
    case TOKEN_SWITCH : "SWITCH"
    case TOKEN_CASE : "CASE"
    case TOKEN_DEFAULT : "DEFAULT"
    case TOKEN_VAR : "VAR"
    case TOKEN_CONST : "CONST"
    case TOKEN_AS : "AS"
    case TOKEN_NEW : "NEW"
    case TOKEN_DELETE : "DELETE"
    case TOKEN_PLUS : "PLUS"
    case TOKEN_MINUS : "MINUS"
    case TOKEN_STAR : "STAR"
    case TOKEN_SLASH : "SLASH"
    case TOKEN_PERCENT : "PERCENT"
    case TOKEN_EQ : "EQ"
    case TOKEN_NE : "NE"
    case TOKEN_LT : "LT"
    case TOKEN_LE : "LE"
    case TOKEN_GT : "GT"
    case TOKEN_GE : "GE"
    case TOKEN_ASSIGN : "ASSIGN"
    case TOKEN_COLON_ASSIGN : "COLON_ASSIGN"
    case TOKEN_PLUS_ASSIGN : "PLUS_ASSIGN"
    case TOKEN_MINUS_ASSIGN : "MINUS_ASSIGN"
    case TOKEN_STAR_ASSIGN : "STAR_ASSIGN"
    case TOKEN_SLASH_ASSIGN : "SLASH_ASSIGN"
    case TOKEN_AND : "AND"
    case TOKEN_OR : "OR"
    case TOKEN_NOT : "NOT"
    case TOKEN_BIT_AND : "BIT_AND"
    case TOKEN_BIT_OR : "BIT_OR"
    case TOKEN_BIT_XOR : "BIT_XOR"
    case TOKEN_BIT_NOT : "BIT_NOT"
    case TOKEN_LSHIFT : "LSHIFT"
    case TOKEN_RSHIFT : "RSHIFT"
    case TOKEN_LSHIFT_ASSIGN : "LSHIFT_ASSIGN"
    case TOKEN_RSHIFT_ASSIGN : "RSHIFT_ASSIGN"
    case TOKEN_AND_ASSIGN : "AND_ASSIGN"
    case TOKEN_OR_ASSIGN : "OR_ASSIGN"
    case TOKEN_XOR_ASSIGN : "XOR_ASSIGN"
    case TOKEN_LPAREN : "LPAREN"
    case TOKEN_RPAREN : "RPAREN"
    case TOKEN_LBRACE : "LBRACE"
    case TOKEN_RBRACE : "RBRACE"
    case TOKEN_LBRACKET : "LBRACKET"
    case TOKEN_RBRACKET : "RBRACKET"
    case TOKEN_COMMA : "COMMA"
    case TOKEN_DOT : "DOT"
    case TOKEN_COLON : "COLON"
    case TOKEN_SEMICOLON : "SEMICOLON"
    case TOKEN_ARROW : "ARROW"
    case TOKEN_QUESTION : "QUESTION"
    case TOKEN_NEWLINE : "NEWLINE"
    default : "UNKNOWN"
    }
}
