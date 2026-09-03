package compile.internal.frontend

struct parser {
    lexer: lexer
    current_token: token
    peek_token: token
    errors: array
}

const token_and = 57
const token_or = 58
const token_bit_and = 60
const token_bit_or = 61
const token_bit_xor = 62
const token_lshift = 64
const token_rshift = 65
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
const token_not = 59
const token_bit_not = 63
const token_eof = 0
const token_ident = 10
const token_int = 11
const token_float = 12
const token_string = 13
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
const token_assign = 51
const token_colon_assign = 52
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
const token_newline = 99

const ast_program = 1
const ast_package = 2
const ast_import = 3
const ast_func_decl = 4
const ast_struct_decl = 5
const ast_enum_decl = 6
const ast_var_decl = 7
const ast_const_decl = 8
const ast_if_stmt = 21
const ast_for_stmt = 22
const ast_while_stmt = 23
const ast_return_stmt = 24
const ast_break_stmt = 25
const ast_continue_stmt = 26
const ast_switch_stmt = 27
const ast_block_stmt = 28
const ast_case_clause = 29
const ast_binary_op = 40
const ast_unary_op = 41
const ast_call_expr = 42
const ast_index_expr = 43
const ast_member_expr = 44
const ast_ident = 47
const ast_int_lit = 48
const ast_float_lit = 49
const ast_string_lit = 50
const ast_bool_lit = 51
const ast_cast_expr = 53
const ast_type_ident = 60
const ast_type_array = 61
const ast_type_ptr = 66

const prec_lowest = 0
const prec_or = 1
const prec_and = 2
const prec_bitwise_or = 3
const prec_bitwise_xor = 4
const prec_bitwise_and = 5
const prec_equals = 6
const prec_comparison = 7
const prec_bitshift = 8
const prec_additive = 9
const prec_multiplicative = 10
const prec_unary = 11
const prec_postfix = 12

func token_precedence(int tok_type) int {
    switch tok_type {
    case token_or : prec_or
    case token_and : prec_and
    case token_bit_or : prec_bitwise_or
    case token_bit_xor : prec_bitwise_xor
    case token_bit_and : prec_bitwise_and
    case token_eq : prec_equals
    case token_ne : prec_equals
    case token_lt : prec_comparison
    case token_le : prec_comparison
    case token_gt : prec_comparison
    case token_ge : prec_comparison
    case token_lshift : prec_bitshift
    case token_rshift : prec_bitshift
    case token_plus : prec_additive
    case token_minus : prec_additive
    case token_star : prec_multiplicative
    case token_slash : prec_multiplicative
    case token_percent : prec_multiplicative
    case token_lparen : prec_postfix
    case token_lbracket : prec_postfix
    case token_dot : prec_postfix
    default : prec_lowest
    }
}

func parser_new(lexer lex) parser {
    p := parser {
        lexer: lex, current_token: token { token_type: 0, value: "", line: 0, column: 0 }, peek_token: token { token_type: 0, value: "", line: 0, column: 0 }, errors: vec[string]()
    }
    parser_next_token(p*)
    parser_next_token(p*)
    p
}

func parser_next_token(p* parser) {
    p.current_token = p.peek_token
    p.peek_token = lexer_next_token(p.lexer*)
}

func parser_current_token_is(p* parser, int tok_type) bool {
    return p.current_token.token_type == tok_type
}

func parser_peek_token_is(p* parser, int tok_type) bool {
    return p.peek_token.token_type == tok_type
}

func parser_expect_peek(p* parser, int tok_type) int {
    if parser_peek_token_is(p, tok_type) {
        parser_next_token(p)
        return 1
    } else {
        parser_add_error(p, "Expected " + token_type_name(tok_type) + " but got " + token_type_name(p.peek_token.token_type))
        return 0
    }
}

func parser_add_error(p* parser, string msg) {
    p.errors.push(msg)
}

func parser_skip_newlines(p* parser) {
    while parser_current_token_is(p, token_newline) {
        parser_next_token(p)
    }
}

func parser_parse_program(p* parser) ast_node* {
    program := ast_new(ast_program, 1, 0)

    while !parser_current_token_is(p, token_eof) {
        parser_skip_newlines(p)

        if parser_current_token_is(p, token_package) {
            pkg := parser_parse_package(p)
            ast_add_child(program, pkg)
        } else if parser_current_token_is(p, token_use) {
            imp := parser_parse_import(p)
            ast_add_child(program, imp)
        } else if parser_current_token_is(p, token_func) {
            func_decl := parser_parse_func_decl(p)
            ast_add_child(program, func_decl)
        } else if parser_current_token_is(p, token_struct) {
            struct_decl := parser_parse_struct_decl(p)
            ast_add_child(program, struct_decl)
        } else if parser_current_token_is(p, token_enum) {
            enum_decl := parser_parse_enum_decl(p)
            ast_add_child(program, enum_decl)
        } else if parser_current_token_is(p, token_var) {
            var_decl := parser_parse_var_decl(p)
            ast_add_child(program, var_decl)
        } else if parser_current_token_is(p, token_const) {
            const_decl := parser_parse_const_decl(p)
            ast_add_child(program, const_decl)
        } else {
            parser_add_error(p, "Unexpected token: " + p.current_token.value)
            parser_next_token(p)
        }
    }

    program
}

func parser_parse_package(p* parser) ast_node* {
    pkg := ast_new(ast_package, p.current_token.line, p.current_token.column)

    if !parser_expect_peek(p, token_ident) {
        return pkg
    }

    ast_set_name(pkg, p.current_token.value)
    parser_next_token(p)

    pkg
}

func parser_parse_import(p* parser) ast_node* {
    imp := ast_new(ast_import, p.current_token.line, p.current_token.column)

    if !parser_expect_peek(p, token_ident) {
        return imp
    }

    path := p.current_token.value
    parser_next_token(p)

    while parser_current_token_is(p, token_dot) {
        parser_next_token(p)
        if parser_current_token_is(p, token_ident) {
            path = path + "." + p.current_token.value
            parser_next_token(p)
        }
    }

    ast_set_string_data(imp, path)
    imp
}

func parser_parse_func_decl(p* parser) ast_node* {
    func_decl := ast_new(ast_func_decl, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    parser_skip_newlines(p)

    if parser_current_token_is(p, token_lparen) {
        receiver := parser_parse_receiver(p)
        ast_add_child(func_decl, receiver)
    }

    if !parser_current_token_is(p, token_ident) {
        parser_add_error(p, "Expected function name")
        return func_decl
    }

    ast_set_name(func_decl, p.current_token.value)
    parser_next_token(p)

    if !parser_expect_peek(p, token_lparen) {
        return func_decl
    }

    params := parser_parse_parameters(p)
    ast_add_child(func_decl, params)

    parser_skip_newlines(p)

    if !parser_current_token_is(p, token_lbrace) {
        ret_types := parser_parse_return_types(p)
        ast_add_child(func_decl, ret_types)
    }

    if parser_current_token_is(p, token_lbrace) {
        body := parser_parse_block(p)
        ast_add_child(func_decl, body)
    }

    func_decl
}

func parser_parse_receiver(p* parser) ast_node* {
    receiver := ast_new(ast_var_decl, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if !parser_current_token_is(p, token_ident) {
        parser_add_error(p, "Expected receiver name")
        return receiver
    }

    ast_set_name(receiver, p.current_token.value)
    parser_next_token(p)

    if !parser_expect_peek(p, token_colon) {
        return receiver
    }

    type_node := parser_parse_type(p)
    ast_set_type_name(receiver, type_node.name)

    if !parser_expect_peek(p, token_rparen) {
        return receiver
    }

    receiver
}

func parser_parse_parameters(p* parser) ast_node* {
    params := ast_new(ast_block_stmt, p.current_token.line, p.current_token.column)

    parser_next_token(p)

    while !parser_current_token_is(p, token_rparen) && !parser_current_token_is(p, token_eof) {
        if parser_current_token_is(p, token_ident) {
            param_name := p.current_token.value
            parser_next_token(p)

            if !parser_expect_peek(p, token_colon) {
                continue
            }

            param_type := parser_parse_type(p)
            param := ast_new(ast_var_decl, p.current_token.line, p.current_token.column)
            ast_set_name(param, param_name)
            ast_set_type_name(param, param_type.name)
            ast_add_child(params, param)
        }

        if parser_current_token_is(p, token_comma) {
            parser_next_token(p)
        } else if !parser_current_token_is(p, token_rparen) {
            parser_add_error(p, "Expected ',' or ')'")
        }
    }

    if parser_current_token_is(p, token_rparen) {
        parser_next_token(p)
    }

    params
}

func parser_parse_return_types(p* parser) ast_node* {
    ret_types := ast_new(ast_block_stmt, p.current_token.line, p.current_token.column)

    if parser_current_token_is(p, token_lparen) {
        parser_next_token(p)
        while !parser_current_token_is(p, token_rparen) && !parser_current_token_is(p, token_eof) {
            ret_type := parser_parse_type(p)
            ast_add_child(ret_types, ret_type)
            if parser_current_token_is(p, token_comma) {
                parser_next_token(p)
            }
        }
        if parser_current_token_is(p, token_rparen) {
            parser_next_token(p)
        }
    } else {
        ret_type := parser_parse_type(p)
        ast_add_child(ret_types, ret_type)
    }

    ret_types
}

func parser_parse_type(p* parser) ast_node* {
    type_node := ast_new(ast_type_ident, p.current_token.line, p.current_token.column)

    if parser_current_token_is(p, token_ident) {
        ast_set_name(type_node, p.current_token.value)
        parser_next_token(p)
    } else if parser_current_token_is(p, token_lbracket) {
        type_node.node_type = ast_type_array
        parser_next_token(p)
        if !parser_current_token_is(p, token_rbracket) {
            parser_add_error(p, "Expected ']'")
        }
        parser_next_token(p)
        elem_type := parser_parse_type(p)
        ast_add_child(type_node, elem_type)
    } else if parser_current_token_is(p, token_bit_and) {
        type_node.node_type = ast_type_ptr
        parser_next_token(p)
        ref_type := parser_parse_type(p)
        ast_add_child(type_node, ref_type)
    }

    type_node
}

func parser_parse_struct_decl(p* parser) ast_node* {
    struct_decl := ast_new(ast_struct_decl, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if !parser_current_token_is(p, token_ident) {
        parser_add_error(p, "Expected struct name")
        return struct_decl
    }

    ast_set_name(struct_decl, p.current_token.value)
    parser_next_token(p)

    if parser_expect_peek(p, token_lbrace) {
        while !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
            parser_skip_newlines(p)
            if parser_current_token_is(p, token_ident) {
                field := ast_new(ast_var_decl, p.current_token.line, p.current_token.column)
                ast_set_name(field, p.current_token.value)
                parser_next_token(p)

                if parser_expect_peek(p, token_colon) {
                    field_type := parser_parse_type(p)
                    ast_set_type_name(field, field_type.name)
                }

                ast_add_child(struct_decl, field)
            }
            parser_skip_newlines(p)
            if parser_current_token_is(p, token_rbrace) {
                break
            }
        }
        parser_next_token(p)
    }

    struct_decl
}

func parser_parse_enum_decl(p* parser) ast_node* {
    enum_decl := ast_new(ast_enum_decl, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if !parser_current_token_is(p, token_ident) {
        parser_add_error(p, "Expected enum name")
        return enum_decl
    }

    ast_set_name(enum_decl, p.current_token.value)
    parser_next_token(p)

    if parser_expect_peek(p, token_lbrace) {
        while !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
            parser_skip_newlines(p)
            if parser_current_token_is(p, token_ident) {
                variant := ast_new(ast_ident, p.current_token.line, p.current_token.column)
                ast_set_name(variant, p.current_token.value)
                parser_next_token(p)
                ast_add_child(enum_decl, variant)
            }
            if parser_current_token_is(p, token_comma) {
                parser_next_token(p)
            }
        }
        parser_next_token(p)
    }

    enum_decl
}

func parser_parse_var_decl(p* parser) ast_node* {
    var_decl := ast_new(ast_var_decl, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if !parser_current_token_is(p, token_ident) {
        parser_add_error(p, "Expected variable name")
        return var_decl
    }

    ast_set_name(var_decl, p.current_token.value)
    parser_next_token(p)

    if parser_current_token_is(p, token_colon) {
        parser_next_token(p)
        var_type := parser_parse_type(p)
        ast_set_type_name(var_decl, var_type.name)
    }

    if parser_current_token_is(p, token_assign) || parser_current_token_is(p, token_colon_assign) {
        parser_next_token(p)
        init_expr := parser_parse_expression(p, prec_lowest)
        ast_add_child(var_decl, init_expr)
    }

    var_decl
}

func parser_parse_const_decl(p* parser) ast_node* {
    const_decl := ast_new(ast_const_decl, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if !parser_current_token_is(p, token_ident) {
        parser_add_error(p, "Expected constant name")
        return const_decl
    }

    ast_set_name(const_decl, p.current_token.value)
    parser_next_token(p)

    if parser_current_token_is(p, token_colon) {
        parser_next_token(p)
        const_type := parser_parse_type(p)
        ast_set_type_name(const_decl, const_type.name)
    }

    if parser_expect_peek(p, token_assign) {
        init_expr := parser_parse_expression(p, prec_lowest)
        ast_add_child(const_decl, init_expr)
    }

    const_decl
}

func parser_parse_block(p* parser) ast_node* {
    block := ast_new(ast_block_stmt, p.current_token.line, p.current_token.column)

    if !parser_expect_peek(p, token_lbrace) {
        return block
    }

    while !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
        parser_skip_newlines(p)
        stmt := parser_parse_statement(p)
        if stmt {
            ast_add_child(block, stmt)
        }
    }

    if parser_current_token_is(p, token_rbrace) {
        parser_next_token(p)
    }

    block
}

func parser_parse_statement(p* parser) ast_node* {
    if parser_current_token_is(p, token_if) {
        parser_parse_if_stmt(p)
    } else if parser_current_token_is(p, token_for) {
        parser_parse_for_stmt(p)
    } else if parser_current_token_is(p, token_while) {
        parser_parse_while_stmt(p)
    } else if parser_current_token_is(p, token_return) {
        parser_parse_return_stmt(p)
    } else if parser_current_token_is(p, token_break) {
        parser_next_token(p)
        ast_new(ast_break_stmt, p.current_token.line, p.current_token.column)
    } else if parser_current_token_is(p, token_continue) {
        parser_next_token(p)
        ast_new(ast_continue_stmt, p.current_token.line, p.current_token.column)
    } else if parser_current_token_is(p, token_switch) {
        parser_parse_switch_stmt(p)
    } else if parser_current_token_is(p, token_lbrace) {
        parser_parse_block(p)
    } else {
        expr := parser_parse_expression(p, prec_lowest)
        if parser_current_token_is(p, token_newline) || parser_current_token_is(p, token_semicolon) {
            parser_next_token(p)
        }
        expr
    }
}

func parser_parse_if_stmt(p* parser) ast_node* {
    if_stmt := ast_new(ast_if_stmt, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    condition := parser_parse_expression(p, prec_lowest)
    ast_add_child(if_stmt, condition)

    if parser_current_token_is(p, token_lbrace) {
        body := parser_parse_block(p)
        ast_add_child(if_stmt, body)
    }

    if parser_current_token_is(p, token_else) {
        parser_next_token(p)
        if parser_current_token_is(p, token_if) {
            else_part := parser_parse_if_stmt(p)
            ast_add_child(if_stmt, else_part)
        } else if parser_current_token_is(p, token_lbrace) {
            else_body := parser_parse_block(p)
            ast_add_child(if_stmt, else_body)
        }
    }

    if_stmt
}

func parser_parse_for_stmt(p* parser) ast_node* {
    for_stmt := ast_new(ast_for_stmt, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    init := parser_parse_statement(p)
    if init {
        ast_add_child(for_stmt, init)
    }

    condition := parser_parse_expression(p, prec_lowest)
    ast_add_child(for_stmt, condition)

    if parser_current_token_is(p, token_lbrace) {
        body := parser_parse_block(p)
        ast_add_child(for_stmt, body)
    }

    for_stmt
}

func parser_parse_while_stmt(p* parser) ast_node* {
    while_stmt := ast_new(ast_while_stmt, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    condition := parser_parse_expression(p, prec_lowest)
    ast_add_child(while_stmt, condition)

    if parser_current_token_is(p, token_lbrace) {
        body := parser_parse_block(p)
        ast_add_child(while_stmt, body)
    }

    while_stmt
}

func parser_parse_return_stmt(p* parser) ast_node* {
    return_stmt := ast_new(ast_return_stmt, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if !parser_current_token_is(p, token_newline) && !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
        expr := parser_parse_expression(p, prec_lowest)
        ast_add_child(return_stmt, expr)
    }

    return_stmt
}

func parser_parse_switch_stmt(p* parser) ast_node* {
    switch_stmt := ast_new(ast_switch_stmt, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    condition := parser_parse_expression(p, prec_lowest)
    ast_add_child(switch_stmt, condition)

    if parser_expect_peek(p, token_lbrace) {
        while !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
            parser_skip_newlines(p)
            if parser_current_token_is(p, token_case) {
                case_clause := ast_new(ast_case_clause, p.current_token.line, p.current_token.column)
                parser_next_token(p)
                case_expr := parser_parse_expression(p, prec_lowest)
                ast_add_child(case_clause, case_expr)

                if parser_expect_peek(p, token_colon) {
                    while !parser_current_token_is(p, token_case) && !parser_current_token_is(p, token_default) && !parser_current_token_is(p, token_rbrace) {
                        parser_skip_newlines(p)
                        if parser_current_token_is(p, token_rbrace) {
                            break
                        }
                        stmt := parser_parse_statement(p)
                        if stmt {
                            ast_add_child(case_clause, stmt)
                        }
                    }
                }
                ast_add_child(switch_stmt, case_clause)
            } else if parser_current_token_is(p, token_default) {
                parser_next_token(p)
                parser_expect_peek(p, token_colon)
                while !parser_current_token_is(p, token_case) && !parser_current_token_is(p, token_rbrace) {
                    parser_skip_newlines(p)
                    if parser_current_token_is(p, token_rbrace) {
                        break
                    }
                    stmt := parser_parse_statement(p)
                    if stmt {
                        ast_add_child(switch_stmt, stmt)
                    }
                }
            }
        }
        parser_next_token(p)
    }

    switch_stmt
}

func parser_parse_expression(p* parser, int precedence) ast_node* {
    parser_parse_infix_expression(p, parser_parse_primary_expression(p), precedence)
}

func parser_parse_primary_expression(p* parser) ast_node* {
    if parser_current_token_is(p, token_ident) {
        ident := ast_new(ast_ident, p.current_token.line, p.current_token.column)
        ast_set_name(ident, p.current_token.value)
        parser_next_token(p)
        ident
    } else if parser_current_token_is(p, token_int) {
        int_lit := ast_new(ast_int_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(int_lit, p.current_token.value)
        parser_next_token(p)
        int_lit
    } else if parser_current_token_is(p, token_float) {
        float_lit := ast_new(ast_float_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(float_lit, p.current_token.value)
        parser_next_token(p)
        float_lit
    } else if parser_current_token_is(p, token_string) {
        string_lit := ast_new(ast_string_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(string_lit, p.current_token.value)
        parser_next_token(p)
        string_lit
    } else if parser_current_token_is(p, token_true) {
        bool_lit := ast_new(ast_bool_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(bool_lit, "true")
        parser_next_token(p)
        bool_lit
    } else if parser_current_token_is(p, token_false) {
        bool_lit := ast_new(ast_bool_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(bool_lit, "false")
        parser_next_token(p)
        bool_lit
    } else if parser_current_token_is(p, token_lparen) {
        parser_next_token(p)
        expr := parser_parse_expression(p, prec_lowest)
        if parser_expect_peek(p, token_rparen) {
        }
        expr
    } else if parser_current_token_is(p, token_minus) || parser_current_token_is(p, token_not) || parser_current_token_is(p, token_bit_not) || parser_current_token_is(p, token_bit_and) {
        op := p.current_token.value
        parser_next_token(p)
        unary := ast_new(ast_unary_op, p.current_token.line, p.current_token.column)
        ast_set_string_data(unary, op)
        operand := parser_parse_expression(p, prec_unary)
        ast_add_child(unary, operand)
        unary
    } else {
        parser_add_error(p, "Unexpected token in expression: " + p.current_token.value)
        ast_new(ast_ident, p.current_token.line, p.current_token.column)
    }
}

func parser_parse_infix_expression(p* parser, left* ast_node, int precedence) ast_node* {
    while precedence < token_precedence(p.current_token.token_type) {
        if parser_current_token_is(p, token_lparen) {
            call := ast_new(ast_call_expr, p.current_token.line, p.current_token.column)
            ast_add_child(call, left)
            parser_next_token(p)
            while !parser_current_token_is(p, token_rparen) && !parser_current_token_is(p, token_eof) {
                arg := parser_parse_expression(p, prec_lowest)
                ast_add_child(call, arg)
                if parser_current_token_is(p, token_comma) {
                    parser_next_token(p)
                }
            }
            parser_expect_peek(p, token_rparen)
            return parser_parse_infix_expression(p, call, precedence)
        } else if parser_current_token_is(p, token_lbracket) {
            index := ast_new(ast_index_expr, p.current_token.line, p.current_token.column)
            ast_add_child(index, left)
            parser_next_token(p)
            idx_expr := parser_parse_expression(p, prec_lowest)
            ast_add_child(index, idx_expr)
            parser_expect_peek(p, token_rbracket)
            return parser_parse_infix_expression(p, index, precedence)
        } else if parser_current_token_is(p, token_dot) {
            member := ast_new(ast_member_expr, p.current_token.line, p.current_token.column)
            ast_add_child(member, left)
            parser_next_token(p)
            if parser_current_token_is(p, token_ident) {
                member_name := ast_new(ast_ident, p.current_token.line, p.current_token.column)
                ast_set_name(member_name, p.current_token.value)
                ast_add_child(member, member_name)
                parser_next_token(p)
            }
            return parser_parse_infix_expression(p, member, precedence)
        } else if parser_current_token_is(p, token_star) || parser_current_token_is(p, token_plus) || parser_current_token_is(p, token_minus) || parser_current_token_is(p, token_slash) || parser_current_token_is(p, token_percent) || parser_current_token_is(p, token_eq) || parser_current_token_is(p, token_ne) || parser_current_token_is(p, token_lt) || parser_current_token_is(p, token_le) || parser_current_token_is(p, token_gt) || parser_current_token_is(p, token_ge) || parser_current_token_is(p, token_and) || parser_current_token_is(p, token_or) || parser_current_token_is(p, token_bit_and) || parser_current_token_is(p, token_bit_or) || parser_current_token_is(p, token_bit_xor) || parser_current_token_is(p, token_lshift) || parser_current_token_is(p, token_rshift) {
            op := p.current_token.value
            op_type := p.current_token.token_type
            parser_next_token(p)
            right := parser_parse_expression(p, token_precedence(op_type))
            binary := ast_new(ast_binary_op, p.current_token.line, p.current_token.column)
            ast_set_string_data(binary, op)
            ast_add_child(binary, left)
            ast_add_child(binary, right)
            return parser_parse_infix_expression(p, binary, precedence)
        } else if parser_current_token_is(p, token_as) {
            parser_next_token(p)
            cast_type := parser_parse_type(p)
            cast := ast_new(ast_cast_expr, p.current_token.line, p.current_token.column)
            ast_add_child(cast, left)
            ast_add_child(cast, cast_type)
            return parser_parse_infix_expression(p, cast, precedence)
        } else {
            return left
        }
    }
    left
}
