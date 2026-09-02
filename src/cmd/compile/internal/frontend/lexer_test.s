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
        tok := lexer_next_token(lex*)
        if tok.token_type == token_eof {
            break
        }
        if tok.token_type == token_newline {
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
    expected.push(token_package)
    expected.push(token_use)
    expected.push(token_func)
    expected.push(token_struct)
    expected.push(token_enum)
    expected.push(token_if)
    expected.push(token_else)
    expected.push(token_for)
    expected.push(token_while)
    expected.push(token_return)
    expected.push(token_break)
    expected.push(token_continue)
    expected.push(token_switch)
    expected.push(token_case)
    expected.push(token_default)
    expected.push(token_var)
    expected.push(token_const)
    expected.push(token_true)
    expected.push(token_false)
    expected.push(token_as)
    expected.push(token_new)
    expected.push(token_delete)

    tokens := vec[token]()
    for {
        tok := lexer_next_token(lex*)
        if tok.token_type == token_eof {
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
        tok := lexer_next_token(lex*)
        if tok.token_type == token_eof {
            break
        }
        if tok.token_type != token_newline {
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
        tok := lexer_next_token(lex*)
        if tok.token_type == token_eof {
            break
        }
        if tok.token_type == token_int {
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
        tok := lexer_next_token(lex*)
        if tok.token_type == token_eof {
            break
        }
        if tok.token_type == token_float {
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
        tok := lexer_next_token(lex*)
        if tok.token_type == token_eof {
            break
        }
        if tok.token_type == token_string {
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
    expected.push(token_colon_assign)
    expected.push(token_eq)
    expected.push(token_ne)
    expected.push(token_le)
    expected.push(token_ge)
    expected.push(token_and)
    expected.push(token_or)
    expected.push(token_lshift)
    expected.push(token_rshift)
    expected.push(token_plus_assign)
    expected.push(token_minus_assign)
    expected.push(token_star_assign)
    expected.push(token_slash_assign)

    tokens := vec[token]()
    for {
        tok := lexer_next_token(lex*)
        if tok.token_type == token_eof {
            break
        }
        if tok.token_type != token_newline {
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
y := 10
    lex := lexer_new(source)

    tokens := vec[token]()
    for {
        tok := lexer_next_token(lex*)
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

    tok1 := lexer_next_token(lex*)
    if tok1.line != 1 {
        return 1
    }

    lexer_next_token(lex*)

    tok2 := lexer_next_token(lex*)
    if tok2.line != 2 {
        return 1
    }

    lexer_next_token(lex*)

    tok3 := lexer_next_token(lex*)
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
        tok := lexer_next_token(lex*)
        if tok.token_type == token_eof {
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
