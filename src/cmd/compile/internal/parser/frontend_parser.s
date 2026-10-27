package compile.internal.parser

struct parser {
    lexer: lexer
    current_token: token
    peek_token: token
    errors: string[]
}

const fp_ast_program = 1
const fp_ast_package = 2
const fp_ast_import = 3
const fp_ast_func_decl = 4
const fp_ast_struct_decl = 5
const fp_ast_enum_decl = 6
const fp_ast_var_decl = 7
const fp_ast_const_decl = 8
const fp_ast_if_stmt = 21
const fp_ast_for_stmt = 22
const fp_ast_while_stmt = 23
const fp_ast_return_stmt = 24
const fp_ast_break_stmt = 25
const fp_ast_continue_stmt = 26
const fp_ast_switch_stmt = 27
const fp_ast_block_stmt = 28
const fp_ast_case_clause = 29
const fp_ast_binary_op = 40
const fp_ast_unary_op = 41
const fp_ast_call_expr = 42
const fp_ast_index_expr = 43
const fp_ast_member_expr = 44
const fp_ast_ident = 47
const fp_ast_int_lit = 48
const fp_ast_float_lit = 49
const fp_ast_string_lit = 50
const fp_ast_bool_lit = 51
const fp_ast_cast_expr = 53
const fp_ast_type_ident = 60
const fp_ast_type_array = 61
const fp_ast_type_ptr = 66

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
    }
    return prec_lowest
}

func parser_new(lexer lex) parser {
    p := parser {
        lexer: lex, current_token: token { token_type: 0, value: "", line: 0, column: 0 }, peek_token: token { token_type: 0, value: "", line: 0, column: 0 }, errors: string[]()
    }
    parser_next_token(p*)
    parser_next_token(p*)
    p
}

func parser_next_token(p* parser) {
    p.current_token = p.peek_token
    p.peek_token = frontend_lexer_next_token(p.lexer*)
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
        message := "Expected " + frontend_token_type_name(tok_type) + " but got " + frontend_token_type_name(p.peek_token.token_type)
        parser_add_error(p, message)
        return 0
    }
}

func parser_add_error(p* parser, string msg) {
    p.errors = append(p.errors, msg)
}

func parser_skip_newlines(p* parser) {
    for parser_current_token_is(p, token_newline) {
        parser_next_token(p)
    }
}

func parser_parse_program(p* parser) ast_node {
    program := ast_new(fp_ast_program, 1, 0)

    for !parser_current_token_is(p, token_eof) {
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

func parser_parse_package(p* parser) ast_node {
    pkg := ast_new(fp_ast_package, p.current_token.line, p.current_token.column)

    if !parser_expect_peek(p, token_ident) {
        return pkg
    }

    ast_set_name(pkg, p.current_token.value)
    parser_next_token(p)

    pkg
}

func parser_parse_import(p* parser) ast_node {
    imp := ast_new(fp_ast_import, p.current_token.line, p.current_token.column)

    if !parser_expect_peek(p, token_ident) {
        return imp
    }

    path := p.current_token.value
    parser_next_token(p)

    for parser_current_token_is(p, token_dot) {
        parser_next_token(p)
        if parser_current_token_is(p, token_ident) {
            path = path + "." + p.current_token.value
            parser_next_token(p)
        }
    }

    ast_set_string_data(imp, path)
    imp
}

func parser_parse_func_decl(p* parser) ast_node {
    func_decl := ast_new(fp_ast_func_decl, p.current_token.line, p.current_token.column)
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

func parser_parse_receiver(p* parser) ast_node {
    receiver := ast_new(fp_ast_var_decl, p.current_token.line, p.current_token.column)
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

func parser_parse_parameters(p* parser) ast_node {
    params := ast_new(fp_ast_block_stmt, p.current_token.line, p.current_token.column)

    parser_next_token(p)

    for !parser_current_token_is(p, token_rparen) && !parser_current_token_is(p, token_eof) {
        if parser_current_token_is(p, token_ident) {
            param_name := p.current_token.value
            parser_next_token(p)

            if !parser_expect_peek(p, token_colon) {
                continue
            }

            param_type := parser_parse_type(p)
            param := ast_new(fp_ast_var_decl, p.current_token.line, p.current_token.column)
            ast_set_name(param, param_name)
            ast_set_type_name(param, param_type.name)
            ast_add_child(params, param)
        }

        if parser_current_token_is(p, token_comma) {
            parser_next_token(p)
        } else if !parser_current_token_is(p, token_rparen) {
            parser_add_error(p, "Expected: ',' or ')'")
        }
    }

    if parser_current_token_is(p, token_rparen) {
        parser_next_token(p)
    }

    params
}

func parser_parse_return_types(p* parser) ast_node {
    ret_types := ast_new(fp_ast_block_stmt, p.current_token.line, p.current_token.column)

    if parser_current_token_is(p, token_lparen) {
        parser_next_token(p)
        for !parser_current_token_is(p, token_rparen) && !parser_current_token_is(p, token_eof) {
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

func parser_parse_type(p* parser) ast_node {
    type_node := ast_new(fp_ast_type_ident, p.current_token.line, p.current_token.column)

    if parser_current_token_is(p, token_ident) {
        ast_set_name(type_node, p.current_token.value)
        parser_next_token(p)
    } else if parser_current_token_is(p, token_lbracket) {
        type_node.node_type = fp_ast_type_array
        parser_next_token(p)
        if !parser_current_token_is(p, token_rbracket) {
            parser_add_error(p, "Expected ']'")
        }
        parser_next_token(p)
        elem_type := parser_parse_type(p)
        ast_add_child(type_node, elem_type)
    } else if parser_current_token_is(p, token_bit_and) {
        type_node.node_type = fp_ast_type_ptr
        parser_next_token(p)
        ref_type := parser_parse_type(p)
        ast_add_child(type_node, ref_type)
    }

    type_node
}

func parser_parse_struct_decl(p* parser) ast_node {
    struct_decl := ast_new(fp_ast_struct_decl, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if !parser_current_token_is(p, token_ident) {
        parser_add_error(p, "Expected struct name")
        return struct_decl
    }

    ast_set_name(struct_decl, p.current_token.value)
    parser_next_token(p)

    if parser_expect_peek(p, token_lbrace) {
        for !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
            parser_skip_newlines(p)
            if parser_current_token_is(p, token_ident) {
                field := ast_new(fp_ast_var_decl, p.current_token.line, p.current_token.column)
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

func parser_parse_enum_decl(p* parser) ast_node {
    enum_decl := ast_new(fp_ast_enum_decl, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if !parser_current_token_is(p, token_ident) {
        parser_add_error(p, "Expected enum name")
        return enum_decl
    }

    ast_set_name(enum_decl, p.current_token.value)
    parser_next_token(p)

    if parser_expect_peek(p, token_lbrace) {
        for !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
            parser_skip_newlines(p)
            if parser_current_token_is(p, token_ident) {
                variant := ast_new(fp_ast_ident, p.current_token.line, p.current_token.column)
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

func parser_parse_var_decl(p* parser) ast_node {
    var_decl := ast_new(fp_ast_var_decl, p.current_token.line, p.current_token.column)
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

func parser_parse_const_decl(p* parser) ast_node {
    const_decl := ast_new(fp_ast_const_decl, p.current_token.line, p.current_token.column)
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

func parser_parse_block(p* parser) ast_node {
    block := ast_new(fp_ast_block_stmt, p.current_token.line, p.current_token.column)

    if !parser_expect_peek(p, token_lbrace) {
        return block
    }

    for !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
        parser_skip_newlines(p)
        stmt := parser_parse_statement(p)
        if stmt.node_type != 0 {
            ast_add_child(block, stmt)
        }
    }

    if parser_current_token_is(p, token_rbrace) {
        parser_next_token(p)
    }

    block
}

func parser_parse_statement(p* parser) ast_node {
    if parser_current_token_is(p, token_if) {
        return parser_parse_if_stmt(p)
    } else if parser_current_token_is(p, token_for) {
        return parser_parse_for_stmt(p)
    } else if parser_current_token_is(p, token_while) {
        return parser_parse_while_stmt(p)
    } else if parser_current_token_is(p, token_return) {
        return parser_parse_return_stmt(p)
    } else if parser_current_token_is(p, token_break) {
        parser_next_token(p)
        return ast_new(fp_ast_break_stmt, p.current_token.line, p.current_token.column)
    } else if parser_current_token_is(p, token_continue) {
        parser_next_token(p)
        return ast_new(fp_ast_continue_stmt, p.current_token.line, p.current_token.column)
    } else if parser_current_token_is(p, token_switch) {
        return parser_parse_switch_stmt(p)
    } else if parser_current_token_is(p, token_lbrace) {
        return parser_parse_block(p)
    } else {
        expr := parser_parse_expression(p, prec_lowest)
        if parser_current_token_is(p, token_newline) || parser_current_token_is(p, token_semicolon) {
            parser_next_token(p)
        }
        return expr
    }
}

func parser_parse_if_stmt(p* parser) ast_node {
    if_stmt := ast_new(fp_ast_if_stmt, p.current_token.line, p.current_token.column)
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

func parser_parse_for_stmt(p* parser) ast_node {
    for_stmt := ast_new(fp_ast_for_stmt, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if parser_current_token_is(p, token_lbrace) {
        body := parser_parse_block(p)
        ast_add_child(for_stmt, body)
        return for_stmt
    }

    if parser_current_token_is(p, token_ident) && parser_peek_token_is(p, token_colon_assign) {
        ident := ast_new(fp_ast_ident, p.current_token.line, p.current_token.column)
        ast_set_name(ident, p.current_token.value)
        parser_next_token(p)
        parser_next_token(p)

        expr := parser_parse_expression(p, prec_lowest)

        init := ast_new(fp_ast_binary_op, p.current_token.line, p.current_token.column)
        ast_add_child(init, ident)
        ast_add_child(init, expr)

        if parser_current_token_is(p, token_semicolon) {
            ast_add_child(for_stmt, init)
            parser_next_token(p)

            condition := parser_parse_expression(p, prec_lowest)
            if condition.node_type != 0 {
                ast_add_child(for_stmt, condition)
            }

            if parser_current_token_is(p, token_semicolon) {
                parser_next_token(p)
                post := parser_parse_expression(p, prec_lowest)
                if post.node_type != 0 {
                    ast_add_child(for_stmt, post)
                }
            }
        } else {
            ast_add_child(for_stmt, init)
        }
    } else if !parser_current_token_is(p, token_semicolon) {
        init := parser_parse_statement(p)

        if parser_current_token_is(p, token_semicolon) {
            ast_add_child(for_stmt, init)
            parser_next_token(p)

            condition := parser_parse_expression(p, prec_lowest)
            if condition.node_type != 0 {
                ast_add_child(for_stmt, condition)
            }

            if parser_current_token_is(p, token_semicolon) {
                parser_next_token(p)
                post := parser_parse_expression(p, prec_lowest)
                if post.node_type != 0 {
                    ast_add_child(for_stmt, post)
                }
            }
        } else {
            ast_add_child(for_stmt, init)
        }
    } else {
        parser_next_token(p)

        condition := parser_parse_expression(p, prec_lowest)
        if condition.node_type != 0 {
            ast_add_child(for_stmt, condition)
        }

        if parser_current_token_is(p, token_semicolon) {
            parser_next_token(p)
            post := parser_parse_expression(p, prec_lowest)
            if post.node_type != 0 {
                ast_add_child(for_stmt, post)
            }
        }
    }

    if parser_current_token_is(p, token_lbrace) {
        body := parser_parse_block(p)
        ast_add_child(for_stmt, body)
    }

    for_stmt
}

func parser_parse_while_stmt(p* parser) ast_node {
    while_stmt := ast_new(fp_ast_while_stmt, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    condition := parser_parse_expression(p, prec_lowest)
    ast_add_child(while_stmt, condition)

    if parser_current_token_is(p, token_lbrace) {
        body := parser_parse_block(p)
        ast_add_child(while_stmt, body)
    }

    while_stmt
}

func parser_parse_return_stmt(p* parser) ast_node {
    return_stmt := ast_new(fp_ast_return_stmt, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    if !parser_current_token_is(p, token_newline) && !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
        expr := parser_parse_expression(p, prec_lowest)
        ast_add_child(return_stmt, expr)
    }

    return_stmt
}

func parser_parse_switch_stmt(p* parser) ast_node {
    switch_stmt := ast_new(fp_ast_switch_stmt, p.current_token.line, p.current_token.column)
    parser_next_token(p)

    condition := parser_parse_expression(p, prec_lowest)
    ast_add_child(switch_stmt, condition)

    if parser_expect_peek(p, token_lbrace) {
        for !parser_current_token_is(p, token_rbrace) && !parser_current_token_is(p, token_eof) {
            parser_skip_newlines(p)
            if parser_current_token_is(p, token_case) {
                case_clause := ast_new(fp_ast_case_clause, p.current_token.line, p.current_token.column)
                parser_next_token(p)
                case_expr := parser_parse_expression(p, prec_lowest)
                ast_add_child(case_clause, case_expr)

                if parser_expect_peek(p, token_colon) {
                    for !parser_current_token_is(p, token_case) && !parser_current_token_is(p, token_default) && !parser_current_token_is(p, token_rbrace) {
                        parser_skip_newlines(p)
                        if parser_current_token_is(p, token_rbrace) {
                            break
                        }
                        stmt := parser_parse_statement(p)
                        if stmt.node_type != 0 {
                            ast_add_child(case_clause, stmt)
                        }
                    }
                }
                ast_add_child(switch_stmt, case_clause)
            } else if parser_current_token_is(p, token_default) {
                parser_next_token(p)
                parser_expect_peek(p, token_colon)
                for !parser_current_token_is(p, token_case) && !parser_current_token_is(p, token_rbrace) {
                    parser_skip_newlines(p)
                    if parser_current_token_is(p, token_rbrace) {
                        break
                    }
                    stmt := parser_parse_statement(p)
                    if stmt.node_type != 0 {
                        ast_add_child(switch_stmt, stmt)
                    }
                }
            }
        }
        parser_next_token(p)
    }

    switch_stmt
}

func parser_parse_expression(p* parser, int precedence) ast_node {
    primary := parser_parse_primary_expression(p)
    return parser_parse_infix_expression(p, primary, precedence)
}

func parser_parse_primary_expression(p* parser) ast_node {
    if parser_current_token_is(p, token_ident) {
        ident := ast_new(fp_ast_ident, p.current_token.line, p.current_token.column)
        ast_set_name(ident, p.current_token.value)
        parser_next_token(p)
        return ident
    } else if parser_current_token_is(p, token_int) {
        int_lit := ast_new(fp_ast_int_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(int_lit, p.current_token.value)
        parser_next_token(p)
        return int_lit
    } else if parser_current_token_is(p, token_float) {
        float_lit := ast_new(fp_ast_float_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(float_lit, p.current_token.value)
        parser_next_token(p)
        return float_lit
    } else if parser_current_token_is(p, token_string) {
        string_lit := ast_new(fp_ast_string_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(string_lit, p.current_token.value)
        parser_next_token(p)
        return string_lit
    } else if parser_current_token_is(p, token_true) {
        bool_lit := ast_new(fp_ast_bool_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(bool_lit, "true")
        parser_next_token(p)
        return bool_lit
    } else if parser_current_token_is(p, token_false) {
        bool_lit := ast_new(fp_ast_bool_lit, p.current_token.line, p.current_token.column)
        ast_set_string_data(bool_lit, "false")
        parser_next_token(p)
        return bool_lit
    } else if parser_current_token_is(p, token_lparen) {
        parser_next_token(p)
        expr := parser_parse_expression(p, prec_lowest)
        if parser_expect_peek(p, token_rparen) {
        }
        return expr
    } else if parser_current_token_is(p, token_minus) || parser_current_token_is(p, token_not) || parser_current_token_is(p, token_bit_not) || parser_current_token_is(p, token_bit_and) {
        op := p.current_token.value
        parser_next_token(p)
        unary := ast_new(fp_ast_unary_op, p.current_token.line, p.current_token.column)
        ast_set_string_data(unary, op)
        operand := parser_parse_expression(p, prec_unary)
        ast_add_child(unary, operand)
        return unary
    } else {
        parser_add_error(p, "Unexpected token in expression: " + p.current_token.value)
        return ast_new(fp_ast_ident, p.current_token.line, p.current_token.column)
    }
}

func parser_parse_infix_expression(p* parser,ast_node left, int precedence) ast_node {
    for precedence < token_precedence(p.current_token.token_type) {
        if parser_current_token_is(p, token_lparen) {
            call := ast_new(fp_ast_call_expr, p.current_token.line, p.current_token.column)
            ast_add_child(call, left)
            parser_next_token(p)
            for !parser_current_token_is(p, token_rparen) && !parser_current_token_is(p, token_eof) {
                arg := parser_parse_expression(p, prec_lowest)
                ast_add_child(call, arg)
                if parser_current_token_is(p, token_comma) {
                    parser_next_token(p)
                }
            }
            parser_expect_peek(p, token_rparen)
            return parser_parse_infix_expression(p, call, precedence)
        } else if parser_current_token_is(p, token_lbracket) {
            index := ast_new(fp_ast_index_expr, p.current_token.line, p.current_token.column)
            ast_add_child(index, left)
            parser_next_token(p)
            idx_expr := parser_parse_expression(p, prec_lowest)
            ast_add_child(index, idx_expr)
            parser_expect_peek(p, token_rbracket)
            return parser_parse_infix_expression(p, index, precedence)
        } else if parser_current_token_is(p, token_dot) {
            member := ast_new(fp_ast_member_expr, p.current_token.line, p.current_token.column)
            ast_add_child(member, left)
            parser_next_token(p)
            if parser_current_token_is(p, token_ident) {
                member_name := ast_new(fp_ast_ident, p.current_token.line, p.current_token.column)
                ast_set_name(member_name, p.current_token.value)
                ast_add_child(member, member_name)
                parser_next_token(p)
            }
            return parser_parse_infix_expression(p, member, precedence)
        } else if parser_current_token_is(p, token_star) || parser_current_token_is(p, token_plus) || parser_current_token_is(p, token_minus) || parser_current_token_is(p, token_slash) || parser_current_token_is(p, token_percent) || parser_current_token_is(p, token_eq) || parser_current_token_is(p, token_ne) || parser_current_token_is(p, token_lt) || parser_current_token_is(p, token_le) || parser_current_token_is(p, token_gt) || parser_current_token_is(p, token_ge) || parser_current_token_is(p, token_and) || parser_current_token_is(p, token_or) || parser_current_token_is(p, token_bit_and) || parser_current_token_is(p, token_bit_or) || parser_current_token_is(p, token_bit_xor) || parser_current_token_is(p, token_lshift) || parser_current_token_is(p, token_rshift) {
            op := p.current_token.value
            op_type := p.current_token.token_type
            parser_next_token(p)
            right_precedence := token_precedence(op_type)
            right := parser_parse_expression(p, right_precedence)
            binary := ast_new(fp_ast_binary_op, p.current_token.line, p.current_token.column)
            ast_set_string_data(binary, op)
            ast_add_child(binary, left)
            ast_add_child(binary, right)
            return parser_parse_infix_expression(p, binary, precedence)
        } else if parser_current_token_is(p, token_as) {
            parser_next_token(p)
            cast_type := parser_parse_type(p)
            cast := ast_new(fp_ast_cast_expr, p.current_token.line, p.current_token.column)
            ast_add_child(cast, left)
            ast_add_child(cast, cast_type)
            return parser_parse_infix_expression(p, cast, precedence)
        } else {
            return left
        }
    }
    left
}
