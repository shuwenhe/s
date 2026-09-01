// S 语言词法分析器 (Lexer)
// 将源代码文本转换为 Token 流

package compile.internal.syntax

// Token 类型定义
enum token_type {
    TOK_EOF = 0,           // 文件结束
    
    // 字面量
    TOK_IDENT = 1,         // 标识符 (foo, bar)
    TOK_NUMBER = 2,        // 数字常量 (123, 0x1F)
    TOK_STRING = 3,        // 字符串常量 ("hello")
    TOK_CHAR = 4,          // 字符常量 ('x')
    
    // 关键字
    TOK_FUNC = 5,          // func
    TOK_STRUCT = 6,        // struct
    TOK_INTERFACE = 7,     // interface
    TOK_VAR = 8,           // var
    TOK_CONST = 9,         // const
    TOK_RETURN = 10,       // return
    TOK_IF = 11,           // if
    TOK_ELSE = 12,         // else
    TOK_FOR = 13,          // for
    TOK_BREAK = 14,        // break
    TOK_CONTINUE = 15,     // continue
    TOK_SWITCH = 16,       // switch
    TOK_CASE = 17,         // case
    TOK_DEFAULT = 18,      // default
    TOK_IMPORT = 19,       // import
    TOK_PACKAGE = 20,      // package
    TOK_TYPE = 21,         // type
    TOK_DEFER = 22,        // defer
    TOK_GO = 23,           // go
    TOK_CHAN = 24,         // chan
    TOK_SELECT = 25,       // select
    TOK_RANGE = 26,        // range
    TOK_MAP = 27,          // map
    TOK_MAKE = 28,         // make
    TOK_LEN = 29,          // len
    TOK_CAP = 30,          // cap
    TOK_APPEND = 31,       // append
    TOK_COPY = 32,         // copy
    TOK_NEW = 33,          // new
    TOK_DELETE = 34,       // delete
    TOK_PANIC = 35,        // panic
    TOK_RECOVER = 36,      // recover
    TOK_TRUE = 37,         // true
    TOK_FALSE = 38,        // false
    TOK_NIL = 39,          // nil
    TOK_IOTA = 40,         // iota
    
    // 操作符
    TOK_PLUS = 41,         // +
    TOK_MINUS = 42,        // -
    TOK_STAR = 43,         // *
    TOK_SLASH = 44,        // /
    TOK_PERCENT = 45,      // %
    TOK_AMPERSAND = 46,    // &
    TOK_PIPE = 47,         // |
    TOK_CARET = 48,        // ^
    TOK_LSHIFT = 49,       // <<
    TOK_RSHIFT = 50,       // >>
    TOK_AMPERSAND_CARET = 51, // &^
    
    TOK_PLUS_EQUAL = 52,   // +=
    TOK_MINUS_EQUAL = 53,  // -=
    TOK_STAR_EQUAL = 54,   // *=
    TOK_SLASH_EQUAL = 55,  // /=
    TOK_PERCENT_EQUAL = 56, // %=
    TOK_AMPERSAND_EQUAL = 57, // &=
    TOK_PIPE_EQUAL = 58,   // |=
    TOK_CARET_EQUAL = 59,  // ^=
    TOK_LSHIFT_EQUAL = 60, // <<=
    TOK_RSHIFT_EQUAL = 61, // >>=
    
    TOK_AMPERSAND_CARET_EQUAL = 62, // &^=
    TOK_AND = 63,          // &&
    TOK_OR = 64,           // ||
    TOK_NOT = 65,          // !
    TOK_EQUAL_EQUAL = 66,  // ==
    TOK_NOT_EQUAL = 67,    // !=
    TOK_LESS = 68,         // <
    TOK_LESS_EQUAL = 69,   // <=
    TOK_GREATER = 70,      // >
    TOK_GREATER_EQUAL = 71, // >=
    
    TOK_EQUAL = 72,        // =
    TOK_COLON_EQUAL = 73,  // :=
    TOK_ARROW = 74,        // <-
    TOK_ELLIPSIS = 75,     // ...
    TOK_COLON = 76,        // :
    TOK_DOT = 77,          // .
    TOK_COMMA = 78,        // ,
    TOK_SEMICOLON = 79,    // ;
    
    // 分隔符
    TOK_LPAREN = 80,       // (
    TOK_RPAREN = 81,       // )
    TOK_LBRACE = 82,       // {
    TOK_RBRACE = 83,       // }
    TOK_LBRACKET = 84,     // [
    TOK_RBRACKET = 85,     // ]
    
    // 特殊
    TOK_NEWLINE = 86,      // 换行符 (某些情况下重要)
    TOK_ERROR = 87,        // 错误 Token
}

// Token 结构体
struct token {
    type_* int           // Token 类型
    value* string        // Token 值 (对于 IDENT, NUMBER, STRING)
    line int             // 源代码行号
    col int              // 源代码列号
}

// 词法分析器状态
struct lexer {
    source* string       // 源代码文本
    pos int              // 当前位置
    line int             // 当前行号
    col int              // 当前列号
    tokens* token        // Token 数组
    token_count int      // Token 数量
    token_capacity int   // Token 数组容量
}

// 创建新的词法分析器
func lexer_new(source* string) lexer* {
    l* := alloc(lexer)
    l.source = source
    l.pos = 0
    l.line = 1
    l.col = 1
    l.token_capacity = 1024
    l.tokens = alloc_array(token, l.token_capacity)
    l.token_count = 0
    
    return l
}

// 获取当前字符
func lexer_current_char(l* lexer) int {
    if l.pos >= len(l.source) {
        return 0  // EOF
    }
    return l.source[l.pos]
}

// 获取下一个字符
func lexer_peek_char(l* lexer, offset int) int {
    pos := l.pos + offset
    if pos >= len(l.source) {
        return 0  // EOF
    }
    return l.source[pos]
}

// 推进到下一个字符
func lexer_advance(l* lexer) {
    if l.pos < len(l.source) {
        if l.source[l.pos] == 10 {  // '\n'
            l.line = l.line + 1
            l.col = 1
        } else {
            l.col = l.col + 1
        }
        l.pos = l.pos + 1
    }
}

// 跳过空格和制表符
func lexer_skip_whitespace(l* lexer) {
    for {
        ch := lexer_current_char(l)
        if ch != 32 && ch != 9 {  // ' ' or '\t'
            break
        }
        lexer_advance(l)
    }
}

// 跳过行注释 (//)
func lexer_skip_line_comment(l* lexer) {
    for {
        ch := lexer_current_char(l)
        if ch == 10 || ch == 0 {  // '\n' or EOF
            break
        }
        lexer_advance(l)
    }
}

// 跳过块注释 (/* ... */)
func lexer_skip_block_comment(l* lexer) {
    lexer_advance(l)  // skip '/'
    lexer_advance(l)  // skip '*'
    
    for {
        ch := lexer_current_char(l)
        if ch == 0 {  // EOF
            break
        }
        if ch == 42 && lexer_peek_char(l, 1) == 47 {  // '*/'
            lexer_advance(l)
            lexer_advance(l)
            break
        }
        lexer_advance(l)
    }
}

// 检查是否为字母或下划线
func is_letter(ch int) int {
    return (ch >= 97 && ch <= 122) ||  // a-z
           (ch >= 65 && ch <= 90) ||   // A-Z
           ch == 95                    // _
}

// 检查是否为数字
func is_digit(ch int) int {
    return ch >= 48 && ch <= 57  // 0-9
}

// 检查是否为字母、数字或下划线
func is_alphanum(ch int) int {
    return is_letter(ch) || is_digit(ch) || ch == 95
}

// 读取标识符或关键字
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
    value* := substring(l.source, start, length)
    
    tok* := alloc(token)
    tok.line = l.line
    tok.col = start_col
    tok.value = value
    
    // 检查关键字
    tok.type_ = lexer_keyword_type(value)
    if tok.type_ == 0 {
        tok.type_ = 1  // TOK_IDENT
    }
    
    return *tok
}

// 检查关键字类型
func lexer_keyword_type(s* string) int {
    if s == nil {
        return 0
    }
    
    // 简单的关键字匹配
    switch len(s) {
    case 2:
        if s == "if" {
            return 11  // TOK_IF
        }
        if s == "go" {
            return 23  // TOK_GO
        }
    case 3:
        if s == "for" {
            return 13  // TOK_FOR
        }
        if s == "var" {
            return 8   // TOK_VAR
        }
        if s == "map" {
            return 27  // TOK_MAP
        }
    case 4:
        if s == "func" {
            return 5   // TOK_FUNC
        }
        if s == "else" {
            return 12  // TOK_ELSE
        }
        if s == "case" {
            return 17  // TOK_CASE
        }
        if s == "type" {
            return 21  // TOK_TYPE
        }
        if s == "true" {
            return 37  // TOK_TRUE
        }
    case 5:
        if s == "const" {
            return 9   // TOK_CONST
        }
        if s == "defer" {
            return 22  // TOK_DEFER
        }
        if s == "false" {
            return 38  // TOK_FALSE
        }
        if s == "iota" {
            return 40  // TOK_IOTA
        }
    case 6:
        if s == "return" {
            return 10  // TOK_RETURN
        }
        if s == "switch" {
            return 16  // TOK_SWITCH
        }
        if s == "struct" {
            return 6   // TOK_STRUCT
        }
        if s == "import" {
            return 19  // TOK_IMPORT
        }
        if s == "select" {
            return 25  // TOK_SELECT
        }
        if s == "delete" {
            return 34  // TOK_DELETE
        }
    case 7:
        if s == "package" {
            return 20  // TOK_PACKAGE
        }
        if s == "default" {
            return 18  // TOK_DEFAULT
        }
    case 9:
        if s == "interface" {
            return 7   // TOK_INTERFACE
        }
    }
    
    return 0
}

// 读取数字
func lexer_read_number(l* lexer) token {
    start := l.pos
    start_col := l.col
    
    // 检查十六进制 (0x)
    if lexer_current_char(l) == 48 && lexer_peek_char(l, 1) == 120 {
        lexer_advance(l)
        lexer_advance(l)
        for {
            ch := lexer_current_char(l)
            if !is_digit(ch) && 
               !(ch >= 97 && ch <= 102) &&  // a-f
               !(ch >= 65 && ch <= 70) {    // A-F
                break
            }
            lexer_advance(l)
        }
    } else {
        // 十进制
        for {
            if !is_digit(lexer_current_char(l)) {
                break
            }
            lexer_advance(l)
        }
        
        // 小数点
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
    value* := substring(l.source, start, length)
    
    tok* := alloc(token)
    tok.line = l.line
    tok.col = start_col
    tok.type_ = 2  // TOK_NUMBER
    tok.value = value
    
    return *tok
}

// 读取字符串
func lexer_read_string(l* lexer) token {
    start_col := l.col
    quote := lexer_current_char(l)  // '"' or '\''
    lexer_advance(l)  // skip opening quote
    
    start := l.pos
    for {
        ch := lexer_current_char(l)
        if ch == 0 || ch == 10 {  // EOF or newline
            break
        }
        if ch == quote {
            break
        }
        if ch == 92 && lexer_peek_char(l, 1) == quote {  // backslash
            lexer_advance(l)
            lexer_advance(l)
        } else {
            lexer_advance(l)
        }
    }
    
    length := l.pos - start
    value* := substring(l.source, start, length)
    
    if lexer_current_char(l) == quote {
        lexer_advance(l)  // skip closing quote
    }
    
    tok* := alloc(token)
    tok.line = l.line
    tok.col = start_col
    tok.type_ = 3  // TOK_STRING
    tok.value = value
    
    return *tok
}

// 添加 Token
func lexer_add_token(l* lexer, tok* token) {
    if l.token_count >= l.token_capacity {
        new_capacity := l.token_capacity * 2
        new_tokens* := alloc_array(token, new_capacity)
        copy_array(new_tokens, l.tokens, l.token_count)
        l.tokens = new_tokens
        l.token_capacity = new_capacity
    }
    l.tokens[l.token_count] = *tok
    l.token_count = l.token_count + 1
}

// 执行词法分析
func lexer_tokenize(l* lexer) {
    for {
        lexer_skip_whitespace(l)
        
        ch := lexer_current_char(l)
        if ch == 0 {  // EOF
            break
        }
        
        // 注释
        if ch == 47 {  // '/'
            if lexer_peek_char(l, 1) == 47 {  // '//'
                lexer_skip_line_comment(l)
                continue
            }
            if lexer_peek_char(l, 1) == 42 {  // '/*'
                lexer_skip_block_comment(l)
                continue
            }
        }
        
        // 标识符或关键字
        if is_letter(ch) {
            tok := lexer_read_ident(l)
            lexer_add_token(l, &tok)
            continue
        }
        
        // 数字
        if is_digit(ch) {
            tok := lexer_read_number(l)
            lexer_add_token(l, &tok)
            continue
        }
        
        // 字符串
        if ch == 34 || ch == 39 {  // '"' or '\''
            tok := lexer_read_string(l)
            lexer_add_token(l, &tok)
            continue
        }
        
        // 操作符和分隔符
        tok_type := 0
        col := l.col
        
        switch ch {
        case 43:  // '+'
            if lexer_peek_char(l, 1) == 61 {  // '+='
                lexer_advance(l)
                tok_type = 52  // TOK_PLUS_EQUAL
            } else {
                tok_type = 41  // TOK_PLUS
            }
        case 45:  // '-'
            if lexer_peek_char(l, 1) == 61 {  // '-='
                lexer_advance(l)
                tok_type = 53  // TOK_MINUS_EQUAL
            } else {
                tok_type = 42  // TOK_MINUS
            }
        case 42:  // '*'
            if lexer_peek_char(l, 1) == 61 {  // '*='
                lexer_advance(l)
                tok_type = 54  // TOK_STAR_EQUAL
            } else {
                tok_type = 43  // TOK_STAR
            }
        case 47:  // '/'
            if lexer_peek_char(l, 1) == 61 {  // '/='
                lexer_advance(l)
                tok_type = 55  // TOK_SLASH_EQUAL
            } else {
                tok_type = 44  // TOK_SLASH
            }
        case 37:  // '%'
            if lexer_peek_char(l, 1) == 61 {  // '%='
                lexer_advance(l)
                tok_type = 56  // TOK_PERCENT_EQUAL
            } else {
                tok_type = 45  // TOK_PERCENT
            }
        case 38:  // '&'
            if lexer_peek_char(l, 1) == 38 {  // '&&'
                lexer_advance(l)
                tok_type = 63  // TOK_AND
            } else if lexer_peek_char(l, 1) == 61 {  // '&='
                lexer_advance(l)
                tok_type = 57  // TOK_AMPERSAND_EQUAL
            } else if lexer_peek_char(l, 1) == 94 {  // '&^'
                lexer_advance(l)
                if lexer_peek_char(l, 1) == 61 {  // '&^='
                    lexer_advance(l)
                    tok_type = 62  // TOK_AMPERSAND_CARET_EQUAL
                } else {
                    tok_type = 51  // TOK_AMPERSAND_CARET
                }
            } else {
                tok_type = 46  // TOK_AMPERSAND
            }
        case 124:  // '|'
            if lexer_peek_char(l, 1) == 124 {  // '||'
                lexer_advance(l)
                tok_type = 64  // TOK_OR
            } else if lexer_peek_char(l, 1) == 61 {  // '|='
                lexer_advance(l)
                tok_type = 58  // TOK_PIPE_EQUAL
            } else {
                tok_type = 47  // TOK_PIPE
            }
        case 94:  // '^'
            if lexer_peek_char(l, 1) == 61 {  // '^='
                lexer_advance(l)
                tok_type = 59  // TOK_CARET_EQUAL
            } else {
                tok_type = 48  // TOK_CARET
            }
        case 60:  // '<'
            if lexer_peek_char(l, 1) == 60 {  // '<<'
                lexer_advance(l)
                if lexer_peek_char(l, 1) == 61 {  // '<<='
                    lexer_advance(l)
                    tok_type = 60  // TOK_LSHIFT_EQUAL
                } else {
                    tok_type = 49  // TOK_LSHIFT
                }
            } else if lexer_peek_char(l, 1) == 45 {  // '<-'
                lexer_advance(l)
                tok_type = 74  // TOK_ARROW
            } else if lexer_peek_char(l, 1) == 61 {  // '<='
                lexer_advance(l)
                tok_type = 69  // TOK_LESS_EQUAL
            } else {
                tok_type = 68  // TOK_LESS
            }
        case 62:  // '>'
            if lexer_peek_char(l, 1) == 62 {  // '>>'
                lexer_advance(l)
                if lexer_peek_char(l, 1) == 61 {  // '>>='
                    lexer_advance(l)
                    tok_type = 61  // TOK_RSHIFT_EQUAL
                } else {
                    tok_type = 50  // TOK_RSHIFT
                }
            } else if lexer_peek_char(l, 1) == 61 {  // '>='
                lexer_advance(l)
                tok_type = 71  // TOK_GREATER_EQUAL
            } else {
                tok_type = 70  // TOK_GREATER
            }
        case 33:  // '!'
            if lexer_peek_char(l, 1) == 61 {  // '!='
                lexer_advance(l)
                tok_type = 67  // TOK_NOT_EQUAL
            } else {
                tok_type = 65  // TOK_NOT
            }
        case 61:  // '='
            if lexer_peek_char(l, 1) == 61 {  // '=='
                lexer_advance(l)
                tok_type = 66  // TOK_EQUAL_EQUAL
            } else {
                tok_type = 72  // TOK_EQUAL
            }
        case 58:  // ':'
            if lexer_peek_char(l, 1) == 61 {  // ':='
                lexer_advance(l)
                tok_type = 73  // TOK_COLON_EQUAL
            } else {
                tok_type = 76  // TOK_COLON
            }
        case 46:  // '.'
            if lexer_peek_char(l, 1) == 46 && lexer_peek_char(l, 2) == 46 {  // '...'
                lexer_advance(l)
                lexer_advance(l)
                tok_type = 75  // TOK_ELLIPSIS
            } else {
                tok_type = 77  // TOK_DOT
            }
        case 44:  // ','
            tok_type = 78  // TOK_COMMA
        case 59:  // ';'
            tok_type = 79  // TOK_SEMICOLON
        case 40:  // '('
            tok_type = 80  // TOK_LPAREN
        case 41:  // ')'
            tok_type = 81  // TOK_RPAREN
        case 123:  // '{'
            tok_type = 82  // TOK_LBRACE
        case 125:  // '}'
            tok_type = 83  // TOK_RBRACE
        case 91:  // '['
            tok_type = 84  // TOK_LBRACKET
        case 93:  // ']'
            tok_type = 85  // TOK_RBRACKET
        case 10:  // '\n'
            tok_type = 86  // TOK_NEWLINE
        default:
            tok_type = 87  // TOK_ERROR
        }
        
        if tok_type > 0 {
            tok* := alloc(token)
            tok.type_ = tok_type
            tok.line = l.line
            tok.col = col
            lexer_add_token(l, tok)
        }
        
        lexer_advance(l)
    }
    
    // 添加 EOF Token
    eof_tok* := alloc(token)
    eof_tok.type_ = 0  // TOK_EOF
    eof_tok.line = l.line
    eof_tok.col = l.col
    lexer_add_token(l, eof_tok)
}

// 获取 Token 数组
func lexer_get_tokens(l* lexer) token* {
    return l.tokens
}

// 获取 Token 数量
func lexer_get_token_count(l* lexer) int {
    return l.token_count
}
