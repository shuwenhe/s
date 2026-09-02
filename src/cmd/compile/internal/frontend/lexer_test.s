package compile.internal.frontend

struct test_case {
    name: string
    input: string
    expected_tokens: token[]
}

func assert_equal_string(string actual, string expected, string test_name) int {
    if actual != expected {
        return 1
    }
    0
}

func assert_equal_int(int actual, int expected, string test_name) int {
    if actual != expected {
        return 1
    }
    0
}

func test_lexer_single_char_tokens() int {
    source := "( ) { } [ ] , . : ; ? ! + - * / % = < > & | ^ ~ "
    lex := lexer_new(source)
    
    tokens := vec[token]()
    for {
        tok := lexer_next_token(&mut lex)
        if tok.token_type == TOKEN_EOF {
            break
        }
        if tok.token_type == TOKEN_NEWLINE {
            continue
        }
        tokens.push(tok)
    }
    
    if tokens.len() != 24 {
        return 1
    }
    0
}

func test_lexer_keywords() int {
    source := "package use func struct enum if else for while return break continue switch case default var const true false as new delete"
    lex := lexer_new(source)
    
    expected := vec[int]()
    expected.push(TOKEN_PACKAGE)
    expected.push(TOKEN_USE)
    expected.push(TOKEN_FUNC)
    expected.push(TOKEN_STRUCT)
    expected.push(TOKEN_ENUM)
    expected.push(TOKEN_IF)
    expected.push(TOKEN_ELSE)
    expected.push(TOKEN_FOR)
    expected.push(TOKEN_WHILE)
    expected.push(TOKEN_RETURN)
    expected.push(TOKEN_BREAK)
    expected.push(TOKEN_CONTINUE)
    expected.push(TOKEN_SWITCH)
    expected.push(TOKEN_CASE)
    expected.push(TOKEN_DEFAULT)
    expected.push(TOKEN_VAR)
    expected.push(TOKEN_CONST)
    expected.push(TOKEN_TRUE)
    expected.push(TOKEN_FALSE)
    expected.push(TOKEN_AS)
    expected.push(TOKEN_NEW)
    expected.push(TOKEN_DELETE)
    
    tokens := vec[token]()
    for {
        tok := lexer_next_token(&mut lex)
        if tok.token_type == TOKEN_EOF {
            break
        }
        tokens.push(tok)
    }
    
    if tokens.len() != expected.len() {
        return 1
    }
    
    for i := 0; i < tokens.len(); i = i + 1 {
        if tokens[i].token_type != expected[i] {
            return 1
        }
    }
    
    0
}

func test_lexer_identifiers() int {
    source := "x foo bar_baz MyVar _private"
    lex := lexer_new(source)
    
    expected := vec[string]()
    expected.push("x")
    expected.push("foo")
    expected.push("bar_baz")
    expected.push("MyVar")
    expected.push("_private")
    
    tokens := vec[token]()
    for {
        tok := lexer_next_token(&mut lex)
        if tok.token_type == TOKEN_EOF {
            break
        }
        if tok.token_type != TOKEN_NEWLINE {
            tokens.push(tok)
        }
    }
    
    if tokens.len() != expected.len() {
        return 1
    }
    
    for i := 0; i < tokens.len(); i = i + 1 {
        if tokens[i].value != expected[i] {
            return 1
        }
    }
    
    0
}

func test_lexer_integers() int {
    source := "0 123 999 1000000"
    lex := lexer_new(source)
    
    expected := vec[string]()
    expected.push("0")
    expected.push("123")
    expected.push("999")
    expected.push("1000000")
    
    tokens := vec[token]()
    for {
        tok := lexer_next_token(&mut lex)
        if tok.token_type == TOKEN_EOF {
            break
        }
        if tok.token_type == TOKEN_INT {
            tokens.push(tok)
        }
    }
    
    if tokens.len() != expected.len() {
        return 1
    }
    
    0
}

func test_lexer_floats() int {
    source := "1.5 3.14 0.001 999.999"
    lex := lexer_new(source)
    
    tokens := vec[token]()
    for {
        tok := lexer_next_token(&mut lex)
        if tok.token_type == TOKEN_EOF {
            break
        }
        if tok.token_type == TOKEN_FLOAT {
            tokens.push(tok)
        }
    }
    
    if tokens.len() != 4 {
        return 1
    }
    
    0
}

func test_lexer_strings() int {
    source := "\"hello\" \"world\" \"test string\""
    lex := lexer_new(source)
    
    tokens := vec[token]()
    for {
        tok := lexer_next_token(&mut lex)
        if tok.token_type == TOKEN_EOF {
            break
        }
        if tok.token_type == TOKEN_STRING {
            tokens.push(tok)
        }
    }
    
    if tokens.len() != 3 {
        return 1
    }
    
    0
}

func test_lexer_operators() int {
    source := ":= == != <= >= && || << >> += -= *= /="
    lex := lexer_new(source)
    
    expected := vec[int]()
    expected.push(TOKEN_COLON_ASSIGN)
    expected.push(TOKEN_EQ)
    expected.push(TOKEN_NE)
    expected.push(TOKEN_LE)
    expected.push(TOKEN_GE)
    expected.push(TOKEN_AND)
    expected.push(TOKEN_OR)
    expected.push(TOKEN_LSHIFT)
    expected.push(TOKEN_RSHIFT)
    expected.push(TOKEN_PLUS_ASSIGN)
    expected.push(TOKEN_MINUS_ASSIGN)
    expected.push(TOKEN_STAR_ASSIGN)
    expected.push(TOKEN_SLASH_ASSIGN)
    
    tokens := vec[token]()
    for {
        tok := lexer_next_token(&mut lex)
        if tok.token_type == TOKEN_EOF {
            break
        }
        if tok.token_type != TOKEN_NEWLINE {
            tokens.push(tok)
        }
    }
    
    if tokens.len() != expected.len() {
        return 1
    }
    
    for i := 0; i < tokens.len(); i = i + 1 {
        if tokens[i].token_type != expected[i] {
            return 1
        }
    }
    
    0
}

func test_lexer_line_comments() int {
    source := "x := 5 // this is a comment
y := 10 // another comment"
    lex := lexer_new(source)
    
    tokens := vec[token]()
    for {
        tok := lexer_next_token(&mut lex)
        if tok.token_type == TOKEN_EOF {
            break
        }
        if tok.token_type != TOKEN_NEWLINE {
            tokens.push(tok)
        }
    }
    
    if tokens.len() < 4 {
        return 1
    }
    
    0
}

func test_lexer_position_tracking() int {
    source := "x
y
z"
    lex := lexer_new(source)
    
    tok1 := lexer_next_token(&mut lex)
    if tok1.line != 1 {
        return 1
    }
    
    lexer_next_token(&mut lex)
    
    tok2 := lexer_next_token(&mut lex)
    if tok2.line != 2 {
        return 1
    }
    
    lexer_next_token(&mut lex)
    
    tok3 := lexer_next_token(&mut lex)
    if tok3.line != 3 {
        return 1
    }
    
    0
}

func test_lexer_complex_expression() int {
    source := "func main() int {
    x := 10 + 20
    y := x * 2
    return y
}"
    lex := lexer_new(source)
    
    tokens := vec[token]()
    for {
        tok := lexer_next_token(&mut lex)
        if tok.token_type == TOKEN_EOF {
            break
        }
        tokens.push(tok)
    }
    
    if tokens.len() < 15 {
        return 1
    }
    
    0
}

func run_lexer_tests() int {
    tests_passed := 0
    tests_failed := 0
    
    if test_lexer_single_char_tokens() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if test_lexer_keywords() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if test_lexer_identifiers() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if test_lexer_integers() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if test_lexer_floats() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if test_lexer_strings() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if test_lexer_operators() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if test_lexer_line_comments() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if test_lexer_position_tracking() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if test_lexer_complex_expression() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }
    
    if tests_failed == 0 {
        0
    } else {
        1
    }
}
