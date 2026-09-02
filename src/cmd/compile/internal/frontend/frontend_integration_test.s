package compile.internal.frontend

func test_frontend_simple_function() int {
    source := "func main() int {
    return 0
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    if prog.children.len() != 1 {
        return 1
    }

    func_decl := prog.children[0]
    if func_decl.node_type != AST_FUNC_DECL {
        return 1
    }

    if func_decl.name != "main" {
        return 1
    }

    0
}

func test_frontend_struct_with_fields() int {
    source := "struct Point {
    x: int
    y: int
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    if prog.children.len() != 1 {
        return 1
    }

    struct_decl := prog.children[0]
    if struct_decl.node_type != AST_STRUCT_DECL {
        return 1
    }

    if struct_decl.name != "Point" {
        return 1
    }

    if struct_decl.children.len() != 2 {
        return 1
    }

    0
}

func test_frontend_package_and_import() int {
    source := "package main
use std.io.println
func test() {
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    if prog.children.len() < 2 {
        return 1
    }

    pkg := prog.children[0]
    if pkg.node_type != AST_PACKAGE {
        return 1
    }

    if pkg.name != "main" {
        return 1
    }

    imp := prog.children[1]
    if imp.node_type != AST_IMPORT {
        return 1
    }

    0
}

func test_frontend_variable_declaration() int {
    source := "x := 10
y: int = 20"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    if prog.children.len() < 2 {
        return 1
    }

    var1 := prog.children[0]
    if var1.node_type != AST_VAR_DECL {
        return 1
    }

    0
}

func test_frontend_binary_expressions() int {
    source := "func test() {
    a := 10 + 20
    b := x * y
    c := a > b
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    0
}

func test_frontend_if_statement() int {
    source := "func test() {
    if x > 0 {
        return 1
    } else {
        return 0
    }
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    0
}

func test_frontend_for_loop() int {
    source := "func test() {
    for i := 0; i < 10; i = i + 1 {
        x := i * 2
    }
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    0
}

func test_frontend_method_with_receiver() int {
    source := "func (m: &MyType) Name() string {
    return m.name
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    if prog.children.len() != 1 {
        return 1
    }

    0
}

func test_frontend_enum_declaration() int {
    source := "enum Color {
    Red,
    Green,
    Blue
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    if prog.children.len() != 1 {
        return 1
    }

    enum_decl := prog.children[0]
    if enum_decl.node_type != AST_ENUM_DECL {
        return 1
    }

    if enum_decl.name != "Color" {
        return 1
    }

    0
}

func test_frontend_complex_expression() int {
    source := "func test() {
    x := (a + b) * c - d / e
    y := x.field[index]
    z := foo(bar(x))
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    0
}

func test_frontend_switch_statement() int {
    source := "func test( x int) int {
    switch x {
    case 1 : return 10
    case 2 : return 20
    default : return 0
    }
}"
    lex := lexer_new(source)
    p := parser_new(lex)
    prog := parser_parse_program(p*)

    if p.errors.len() > 0 {
        return 1
    }

    0
}

func run_frontend_integration_tests() int {
    tests_passed := 0
    tests_failed := 0

    if test_frontend_simple_function() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_struct_with_fields() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_package_and_import() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_variable_declaration() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_binary_expressions() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_if_statement() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_for_loop() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_method_with_receiver() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_enum_declaration() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_complex_expression() == 0 {
        tests_passed = tests_passed + 1
    } else {
        tests_failed = tests_failed + 1
    }

    if test_frontend_switch_statement() == 0 {
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
