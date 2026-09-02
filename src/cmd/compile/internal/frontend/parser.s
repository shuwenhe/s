package compile.internal.frontend

struct parser {
    lexer: lexer
    current_token: token
    peek_token: token
    errors: string[]
}

const PREC_LOWEST = 0
const PREC_OR = 1
const PREC_AND = 2
const PREC_BITWISE_OR = 3
const PREC_BITWISE_XOR = 4
const PREC_BITWISE_AND = 5
const PREC_EQUALS = 6
const PREC_COMPARISON = 7
const PREC_BITSHIFT = 8
const PREC_ADDITIVE = 9
const PREC_MULTIPLICATIVE = 10
const PREC_UNARY = 11
const PREC_POSTFIX = 12

func token_precedence(int tok_type) int {
    switch tok_type {
    case TOKEN_OR : PREC_OR
    case TOKEN_AND : PREC_AND
    case TOKEN_BIT_OR : PREC_BITWISE_OR
    case TOKEN_BIT_XOR : PREC_BITWISE_XOR
    case TOKEN_BIT_AND : PREC_BITWISE_AND
    case TOKEN_EQ : PREC_EQUALS
    case TOKEN_NE : PREC_EQUALS
    case TOKEN_LT : PREC_COMPARISON
    case TOKEN_LE : PREC_COMPARISON
    case TOKEN_GT : PREC_COMPARISON
    case TOKEN_GE : PREC_COMPARISON
    case TOKEN_LSHIFT : PREC_BITSHIFT
    case TOKEN_RSHIFT : PREC_BITSHIFT
    case TOKEN_PLUS : PREC_ADDITIVE
    case TOKEN_MINUS : PREC_ADDITIVE
    case TOKEN_STAR : PREC_MULTIPLICATIVE
    case TOKEN_SLASH : PREC_MULTIPLICATIVE
    case TOKEN_PERCENT : PREC_MULTIPLICATIVE
    case TOKEN_LPAREN : PREC_POSTFIX
    case TOKEN_LBRACKET : PREC_POSTFIX
    case TOKEN_DOT : PREC_POSTFIX
    default : PREC_LOWEST
    }
}

func parser_new(lex: lexer) parser {
    p := parser {
        lexer: lex,
        current_token: token { token_type: 0, value: "", line: 0, column: 0 },
        peek_token: token { token_type: 0, value: "", line: 0, column: 0 },
        errors: vec[string]()
    }
    parser_next_token(p*)
    parser_next_token(p*)
    p
}

func parser_next_token(p* parser) {
    p.current_token = p.peek_token
    p.peek_token = lexer_next_token(&mut p.lexer)
}

func parser_current_token_is(p* parser, int tok_type) int {
    p.current_token.token_type == tok_type
}

func parser_peek_token_is(p* parser, int tok_type) int {
    p.peek_token.token_type == tok_type
}

func parser_expect_peek(p* parser, int tok_type) int {
    if parser_peek_token_is(p, tok_type) {
        parser_next_token(p)
        1
    } else {
        parser_add_error(p, "Expected " + token_type_name(tok_type) + " but got " + token_type_name(p.peek_token.token_type))
        0
    }
}

func parser_add_error(p* parser, string msg) {
    p.errors.push(msg)
}

func parser_skip_newlines(p* parser) {
    while parser_current_token_is(p, TOKEN_NEWLINE) {
        parser_next_token(p)
    }
}

func parser_parse_program(p* parser) &ast_node {
    program := ast_new(AST_PROGRAM, 1, 0)
    
    while !parser_current_token_is(p, TOKEN_EOF) {
        parser_skip_newlines(p)
        
        if parser_current_token_is(p, TOKEN_PACKAGE) {
            pkg := parser_parse_package(p)
            ast_add_child(program, pkg)
        } else if parser_current_token_is(p, TOKEN_USE) {
            imp := parser_parse_import(p)
            ast_add_child(program, imp)
        } else if parser_current_token_is(p, TOKEN_FUNC) {
            func_decl := parser_parse_func_decl(p)
            ast_add_child(program, func_decl)
        } else if parser_current_token_is(p, TOKEN_STRUCT) {
            struct_decl := parser_parse_struct_decl(p)
            ast_add_child(program, struct_decl)
        } else if parser_current_token_is(p, TOKEN_ENUM) {
            enum_decl := parser_parse_enum_decl(p)
            ast_add_child(program, enum_decl)
        } else if parser_current_token_is(p, TOKEN_VAR) {
            var_decl := parser_parse_var_decl(p)
            ast_add_child(program, var_decl)
        } else if parser_current_token_is(p, TOKEN_CONST) {
            const_decl := parser_parse_const_decl(p)
            ast_add_child(program, const_decl)
        } else {
            parser_add_error(p, "Unexpected token: " + p.current_token.value)
            parser_next_token(p)
        }
    }
    
    program
}

func parser_parse_package(p* parser) &ast_node {
    pkg := ast_new(AST_PACKAGE, p.current_token.line, p.current_token.column)
    
    if !parser_expect_peek(p, TOKEN_IDENT) {
        return pkg
    }
    
    ast_set_name(pkg, p.current_token.value)
    parser_next_token(p)
    
    pkg
}

func parser_parse_import(p* parser) &ast_node {
    imp := ast_new(AST_IMPORT, p.current_token.line, p.current_token.column)
    
    if !parser_expect_peek(p, TOKEN_IDENT) {
        return imp
    }
    
    path := p.current_token.value
    parser_next_token(p)
    
    while parser_current_token_is(p, TOKEN_DOT) {
        parser_next_token(p)
        if parser_current_token_is(p, TOKEN_IDENT) {
            path = path + "." + p.current_token.value
            parser_next_token(p)
        }
    }
    
    ast_set_string_data(imp, path)
    imp
}

func parser_parse_func_decl(p* parser) &ast_node {
    func_decl := ast_new(AST_FUNC_DECL, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    parser_skip_newlines(p)
    
    if parser_current_token_is(p, TOKEN_LPAREN) {
        receiver := parser_parse_receiver(p)
        ast_add_child(func_decl, receiver)
    }
    
    if !parser_current_token_is(p, TOKEN_IDENT) {
        parser_add_error(p, "Expected function name")
        return func_decl
    }
    
    ast_set_name(func_decl, p.current_token.value)
    parser_next_token(p)
    
    if !parser_expect_peek(p, TOKEN_LPAREN) {
        return func_decl
    }
    
    params := parser_parse_parameters(p)
    ast_add_child(func_decl, params)
    
    parser_skip_newlines(p)
    
    if !parser_current_token_is(p, TOKEN_LBRACE) {
        ret_types := parser_parse_return_types(p)
        ast_add_child(func_decl, ret_types)
    }
    
    if parser_current_token_is(p, TOKEN_LBRACE) {
        body := parser_parse_block(p)
        ast_add_child(func_decl, body)
    }
    
    func_decl
}

func parser_parse_receiver(p* parser) &ast_node {
    receiver := ast_new(AST_VAR_DECL, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    if !parser_current_token_is(p, TOKEN_IDENT) {
        parser_add_error(p, "Expected receiver name")
        return receiver
    }
    
    ast_set_name(receiver, p.current_token.value)
    parser_next_token(p)
    
    if !parser_expect_peek(p, TOKEN_COLON) {
        return receiver
    }
    
    type_node := parser_parse_type(p)
    ast_set_type_name(receiver, type_node.name)
    
    if !parser_expect_peek(p, TOKEN_RPAREN) {
        return receiver
    }
    
    receiver
}

func parser_parse_parameters(p* parser) &ast_node {
    params := ast_new(AST_BLOCK_STMT, p.current_token.line, p.current_token.column)
    
    parser_next_token(p)
    
    while !parser_current_token_is(p, TOKEN_RPAREN) && !parser_current_token_is(p, TOKEN_EOF) {
        if parser_current_token_is(p, TOKEN_IDENT) {
            param_name := p.current_token.value
            parser_next_token(p)
            
            if !parser_expect_peek(p, TOKEN_COLON) {
                continue
            }
            
            param_type := parser_parse_type(p)
            param := ast_new(AST_VAR_DECL, p.current_token.line, p.current_token.column)
            ast_set_name(param, param_name)
            ast_set_type_name(param, param_type.name)
            ast_add_child(params, param)
        }
        
        if parser_current_token_is(p, TOKEN_COMMA) {
            parser_next_token(p)
        } else if !parser_current_token_is(p, TOKEN_RPAREN) {
            parser_add_error(p, "Expected ',' or ')'")
        }
    }
    
    if parser_current_token_is(p, TOKEN_RPAREN) {
        parser_next_token(p)
    }
    
    params
}

func parser_parse_return_types(p* parser) &ast_node {
    ret_types := ast_new(AST_BLOCK_STMT, p.current_token.line, p.current_token.column)
    
    if parser_current_token_is(p, TOKEN_LPAREN) {
        parser_next_token(p)
        while !parser_current_token_is(p, TOKEN_RPAREN) && !parser_current_token_is(p, TOKEN_EOF) {
            ret_type := parser_parse_type(p)
            ast_add_child(ret_types, ret_type)
            if parser_current_token_is(p, TOKEN_COMMA) {
                parser_next_token(p)
            }
        }
        if parser_current_token_is(p, TOKEN_RPAREN) {
            parser_next_token(p)
        }
    } else {
        ret_type := parser_parse_type(p)
        ast_add_child(ret_types, ret_type)
    }
    
    ret_types
}

func parser_parse_type(p* parser) &ast_node {
    type_node := ast_new(AST_TYPE_IDENT, p.current_token.line, p.current_token.column)
    
    if parser_current_token_is(p, TOKEN_IDENT) {
        ast_set_name(type_node, p.current_token.value)
        parser_next_token(p)
    } else if parser_current_token_is(p, TOKEN_LBRACKET) {
        type_node.node_type = AST_TYPE_ARRAY
        parser_next_token(p)
        if !parser_current_token_is(p, TOKEN_RBRACKET) {
            parser_add_error(p, "Expected ']'")
        }
        parser_next_token(p)
        elem_type := parser_parse_type(p)
        ast_add_child(type_node, elem_type)
    } else if parser_current_token_is(p, TOKEN_BIT_AND) {
        type_node.node_type = AST_TYPE_PTR
        parser_next_token(p)
        ref_type := parser_parse_type(p)
        ast_add_child(type_node, ref_type)
    }
    
    type_node
}

func parser_parse_struct_decl(p* parser) &ast_node {
    struct_decl := ast_new(AST_STRUCT_DECL, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    if !parser_current_token_is(p, TOKEN_IDENT) {
        parser_add_error(p, "Expected struct name")
        return struct_decl
    }
    
    ast_set_name(struct_decl, p.current_token.value)
    parser_next_token(p)
    
    if parser_expect_peek(p, TOKEN_LBRACE) {
        while !parser_current_token_is(p, TOKEN_RBRACE) && !parser_current_token_is(p, TOKEN_EOF) {
            parser_skip_newlines(p)
            if parser_current_token_is(p, TOKEN_IDENT) {
                field := ast_new(AST_VAR_DECL, p.current_token.line, p.current_token.column)
                ast_set_name(field, p.current_token.value)
                parser_next_token(p)
                
                if parser_expect_peek(p, TOKEN_COLON) {
                    field_type := parser_parse_type(p)
                    ast_set_type_name(field, field_type.name)
                }
                
                ast_add_child(struct_decl, field)
            }
            parser_skip_newlines(p)
            if parser_current_token_is(p, TOKEN_RBRACE) {
                break
            }
        }
        parser_next_token(p)
    }
    
    struct_decl
}

func parser_parse_enum_decl(p* parser) &ast_node {
    enum_decl := ast_new(AST_ENUM_DECL, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    if !parser_current_token_is(p, TOKEN_IDENT) {
        parser_add_error(p, "Expected enum name")
        return enum_decl
    }
    
    ast_set_name(enum_decl, p.current_token.value)
    parser_next_token(p)
    
    if parser_expect_peek(p, TOKEN_LBRACE) {
        while !parser_current_token_is(p, TOKEN_RBRACE) && !parser_current_token_is(p, TOKEN_EOF) {
            parser_skip_newlines(p)
            if parser_current_token_is(p, TOKEN_IDENT) {
                variant := ast_new(AST_IDENT, p.current_token.line, p.current_token.column)
                ast_set_name(variant, p.current_token.value)
                parser_next_token(p)
                ast_add_child(enum_decl, variant)
            }
            if parser_current_token_is(p, TOKEN_COMMA) {
                parser_next_token(p)
            }
        }
        parser_next_token(p)
    }
    
    enum_decl
}

func parser_parse_var_decl(p* parser) &ast_node {
    var_decl := ast_new(AST_VAR_DECL, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    if !parser_current_token_is(p, TOKEN_IDENT) {
        parser_add_error(p, "Expected variable name")
        return var_decl
    }
    
    ast_set_name(var_decl, p.current_token.value)
    parser_next_token(p)
    
    if parser_current_token_is(p, TOKEN_COLON) {
        parser_next_token(p)
        var_type := parser_parse_type(p)
        ast_set_type_name(var_decl, var_type.name)
    }
    
    if parser_current_token_is(p, TOKEN_ASSIGN) || parser_current_token_is(p, TOKEN_COLON_ASSIGN) {
        parser_next_token(p)
        init_expr := parser_parse_expression(p, PREC_LOWEST)
        ast_add_child(var_decl, init_expr)
    }
    
    var_decl
}

func parser_parse_const_decl(p* parser) &ast_node {
    const_decl := ast_new(AST_CONST_DECL, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    if !parser_current_token_is(p, TOKEN_IDENT) {
        parser_add_error(p, "Expected constant name")
        return const_decl
    }
    
    ast_set_name(const_decl, p.current_token.value)
    parser_next_token(p)
    
    if parser_current_token_is(p, TOKEN_COLON) {
        parser_next_token(p)
        const_type := parser_parse_type(p)
        ast_set_type_name(const_decl, const_type.name)
    }
    
    if parser_expect_peek(p, TOKEN_ASSIGN) {
        init_expr := parser_parse_expression(p, PREC_LOWEST)
        ast_add_child(const_decl, init_expr)
    }
    
    const_decl
}

func parser_parse_block(p* parser) &ast_node {
    block := ast_new(AST_BLOCK_STMT, p.current_token.line, p.current_token.column)
    
    if !parser_expect_peek(p, TOKEN_LBRACE) {
        return block
    }
    
    while !parser_current_token_is(p, TOKEN_RBRACE) && !parser_current_token_is(p, TOKEN_EOF) {
        parser_skip_newlines(p)
        stmt := parser_parse_statement(p)
        if stmt != 0 {
            ast_add_child(block, stmt)
        }
    }
    
    if parser_current_token_is(p, TOKEN_RBRACE) {
        parser_next_token(p)
    }
    
    block
}

func parser_parse_statement(p* parser) &ast_node {
    if parser_current_token_is(p, TOKEN_IF) {
        parser_parse_if_stmt(p)
    } else if parser_current_token_is(p, TOKEN_FOR) {
        parser_parse_for_stmt(p)
    } else if parser_current_token_is(p, TOKEN_WHILE) {
        parser_parse_while_stmt(p)
    } else if parser_current_token_is(p, TOKEN_RETURN) {
        parser_parse_return_stmt(p)
    } else if parser_current_token_is(p, TOKEN_BREAK) {
        parser_next_token(p)
        ast_new(AST_BREAK_STMT, p.current_token.line, p.current_token.column)
    } else if parser_current_token_is(p, TOKEN_CONTINUE) {
        parser_next_token(p)
        ast_new(AST_CONTINUE_STMT, p.current_token.line, p.current_token.column)
    } else if parser_current_token_is(p, TOKEN_SWITCH) {
        parser_parse_switch_stmt(p)
    } else if parser_current_token_is(p, TOKEN_LBRACE) {
        parser_parse_block(p)
    } else {
        expr := parser_parse_expression(p, PREC_LOWEST)
        if parser_current_token_is(p, TOKEN_NEWLINE) || parser_current_token_is(p, TOKEN_SEMICOLON) {
            parser_next_token(p)
        }
        expr
    }
}

func parser_parse_if_stmt(p* parser) &ast_node {
    if_stmt := ast_new(AST_IF_STMT, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    condition := parser_parse_expression(p, PREC_LOWEST)
    ast_add_child(if_stmt, condition)
    
    if parser_current_token_is(p, TOKEN_LBRACE) {
        body := parser_parse_block(p)
        ast_add_child(if_stmt, body)
    }
    
    if parser_current_token_is(p, TOKEN_ELSE) {
        parser_next_token(p)
        if parser_current_token_is(p, TOKEN_IF) {
            else_part := parser_parse_if_stmt(p)
            ast_add_child(if_stmt, else_part)
        } else if parser_current_token_is(p, TOKEN_LBRACE) {
            else_body := parser_parse_block(p)
            ast_add_child(if_stmt, else_body)
        }
    }
    
    if_stmt
}

func parser_parse_for_stmt(p* parser) &ast_node {
    for_stmt := ast_new(AST_FOR_STMT, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    init := parser_parse_statement(p)
    if init != 0 {
        ast_add_child(for_stmt, init)
    }
    
    condition := parser_parse_expression(p, PREC_LOWEST)
    ast_add_child(for_stmt, condition)
    
    if parser_current_token_is(p, TOKEN_LBRACE) {
        body := parser_parse_block(p)
        ast_add_child(for_stmt, body)
    }
    
    for_stmt
}

func parser_parse_while_stmt(p* parser) &ast_node {
    while_stmt := ast_new(AST_WHILE_STMT, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    condition := parser_parse_expression(p, PREC_LOWEST)
    ast_add_child(while_stmt, condition)
    
    if parser_current_token_is(p, TOKEN_LBRACE) {
        body := parser_parse_block(p)
        ast_add_child(while_stmt, body)
    }
    
    while_stmt
}

func parser_parse_return_stmt(p* parser) &ast_node {
    return_stmt := ast_new(AST_RETURN_STMT, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    if !parser_current_token_is(p, TOKEN_NEWLINE) && !parser_current_token_is(p, TOKEN_RBRACE) && !parser_current_token_is(p, TOKEN_EOF) {
        expr := parser_parse_expression(p, PREC_LOWEST)
        ast_add_child(return_stmt, expr)
    }
    
    return_stmt
}

func parser_parse_switch_stmt(p* parser) &ast_node {
    switch_stmt := ast_new(AST_SWITCH_STMT, p.current_token.line, p.current_token.column)
    parser_next_token(p)
    
    condition := parser_parse_expression(p, PREC_LOWEST)
    ast_add_child(switch_stmt, condition)
    
    if parser_expect_peek(p, TOKEN_LBRACE) {
        while !parser_current_token_is(p, TOKEN_RBRACE) && !parser_current_token_is(p, TOKEN_EOF) {
            parser_skip_newlines(p)
            if parser_current_token_is(p, TOKEN_CASE) {
                case_clause := ast_new(AST_CASE_CLAUSE, p.current_token.line, p.current_token.column)
                parser_next_token(p)
                case_expr := parser_parse_expression(p, PREC_LOWEST)
                ast_add_child(case_clause, case_expr)
                
                if parser_expect_peek(p, TOKEN_COLON) {
                    while !parser_current_token_is(p, TOKEN_CASE) && !parser_current_token_is(p, TOKEN_DEFAULT) && !parser_current_token_is(p, TOKEN_RBRACE) {
                        parser_skip_newlines(p)
                        if parser_current_token_is(p, TOKEN_RBRACE) {
                            break
                        }
                        stmt := parser_parse_statement(p)
                        if stmt != 0 {
                            ast_add_child(case_clause, stmt)
                        }
                    }
                }
                ast_add_child(switch_stmt, case_clause)
            } else if parser_current_token_is(p, TOKEN_DEFAULT) {
                parser_next_token(p)
                parser_expect_peek(p, TOKEN_COLON)
                while !parser_current_token_is(p, TOKEN_CASE) && !parser_current_token_is(p, TOKEN_RBRACE) {
                    parser_skip_newlines(p)
                    if parser_current_token_is(p, TOKEN_RBRACE) {
                        break
                    }
                    stmt := parser_parse_statement(p)
                    if stmt != 0 {
                        ast_add_child(switch_stmt, stmt)
                    }
                }
            }
        }
        parser_next_token(p)
    }
    
    switch_stmt
}

func parser_parse_expression(p* parser, int precedence) &ast_node {
    parser_parse_infix_expression(p, parser_parse_primary_expression(p), precedence)
}

func parser_parse_primary_expression(p* parser) &ast_node {
    if parser_current_token_is(p, TOKEN_IDENT) {
        ident := ast_new(AST_IDENT, p.current_token.line, p.current_token.column)
        ast_set_name(ident, p.current_token.value)
        parser_next_token(p)
        ident
    } else if parser_current_token_is(p, TOKEN_INT) {
        int_lit := ast_new(AST_INT_LIT, p.current_token.line, p.current_token.column)
        ast_set_string_data(int_lit, p.current_token.value)
        parser_next_token(p)
        int_lit
    } else if parser_current_token_is(p, TOKEN_FLOAT) {
        float_lit := ast_new(AST_FLOAT_LIT, p.current_token.line, p.current_token.column)
        ast_set_string_data(float_lit, p.current_token.value)
        parser_next_token(p)
        float_lit
    } else if parser_current_token_is(p, TOKEN_STRING) {
        string_lit := ast_new(AST_STRING_LIT, p.current_token.line, p.current_token.column)
        ast_set_string_data(string_lit, p.current_token.value)
        parser_next_token(p)
        string_lit
    } else if parser_current_token_is(p, TOKEN_TRUE) {
        bool_lit := ast_new(AST_BOOL_LIT, p.current_token.line, p.current_token.column)
        ast_set_string_data(bool_lit, "true")
        parser_next_token(p)
        bool_lit
    } else if parser_current_token_is(p, TOKEN_FALSE) {
        bool_lit := ast_new(AST_BOOL_LIT, p.current_token.line, p.current_token.column)
        ast_set_string_data(bool_lit, "false")
        parser_next_token(p)
        bool_lit
    } else if parser_current_token_is(p, TOKEN_LPAREN) {
        parser_next_token(p)
        expr := parser_parse_expression(p, PREC_LOWEST)
        if parser_expect_peek(p, TOKEN_RPAREN) {
        }
        expr
    } else if parser_current_token_is(p, TOKEN_MINUS) || parser_current_token_is(p, TOKEN_NOT) || parser_current_token_is(p, TOKEN_BIT_NOT) || parser_current_token_is(p, TOKEN_BIT_AND) {
        op := p.current_token.value
        parser_next_token(p)
        unary := ast_new(AST_UNARY_OP, p.current_token.line, p.current_token.column)
        ast_set_string_data(unary, op)
        operand := parser_parse_expression(p, PREC_UNARY)
        ast_add_child(unary, operand)
        unary
    } else {
        parser_add_error(p, "Unexpected token in expression: " + p.current_token.value)
        ast_new(AST_IDENT, p.current_token.line, p.current_token.column)
    }
}

func parser_parse_infix_expression(p* parser, left* ast_node, int precedence) &ast_node {
    while precedence < token_precedence(p.current_token.token_type) {
        if parser_current_token_is(p, TOKEN_LPAREN) {
            call := ast_new(AST_CALL_EXPR, p.current_token.line, p.current_token.column)
            ast_add_child(call, left)
            parser_next_token(p)
            while !parser_current_token_is(p, TOKEN_RPAREN) && !parser_current_token_is(p, TOKEN_EOF) {
                arg := parser_parse_expression(p, PREC_LOWEST)
                ast_add_child(call, arg)
                if parser_current_token_is(p, TOKEN_COMMA) {
                    parser_next_token(p)
                }
            }
            parser_expect_peek(p, TOKEN_RPAREN)
            return parser_parse_infix_expression(p, call, precedence)
        } else if parser_current_token_is(p, TOKEN_LBRACKET) {
            index := ast_new(AST_INDEX_EXPR, p.current_token.line, p.current_token.column)
            ast_add_child(index, left)
            parser_next_token(p)
            idx_expr := parser_parse_expression(p, PREC_LOWEST)
            ast_add_child(index, idx_expr)
            parser_expect_peek(p, TOKEN_RBRACKET)
            return parser_parse_infix_expression(p, index, precedence)
        } else if parser_current_token_is(p, TOKEN_DOT) {
            member := ast_new(AST_MEMBER_EXPR, p.current_token.line, p.current_token.column)
            ast_add_child(member, left)
            parser_next_token(p)
            if parser_current_token_is(p, TOKEN_IDENT) {
                member_name := ast_new(AST_IDENT, p.current_token.line, p.current_token.column)
                ast_set_name(member_name, p.current_token.value)
                ast_add_child(member, member_name)
                parser_next_token(p)
            }
            return parser_parse_infix_expression(p, member, precedence)
        } else if parser_current_token_is(p, TOKEN_STAR) || parser_current_token_is(p, TOKEN_PLUS) || parser_current_token_is(p, TOKEN_MINUS) || parser_current_token_is(p, TOKEN_SLASH) || parser_current_token_is(p, TOKEN_PERCENT) || parser_current_token_is(p, TOKEN_EQ) || parser_current_token_is(p, TOKEN_NE) || parser_current_token_is(p, TOKEN_LT) || parser_current_token_is(p, TOKEN_LE) || parser_current_token_is(p, TOKEN_GT) || parser_current_token_is(p, TOKEN_GE) || parser_current_token_is(p, TOKEN_AND) || parser_current_token_is(p, TOKEN_OR) || parser_current_token_is(p, TOKEN_BIT_AND) || parser_current_token_is(p, TOKEN_BIT_OR) || parser_current_token_is(p, TOKEN_BIT_XOR) || parser_current_token_is(p, TOKEN_LSHIFT) || parser_current_token_is(p, TOKEN_RSHIFT) {
            op := p.current_token.value
            op_type := p.current_token.token_type
            parser_next_token(p)
            right := parser_parse_expression(p, token_precedence(op_type))
            binary := ast_new(AST_BINARY_OP, p.current_token.line, p.current_token.column)
            ast_set_string_data(binary, op)
            ast_add_child(binary, left)
            ast_add_child(binary, right)
            return parser_parse_infix_expression(p, binary, precedence)
        } else if parser_current_token_is(p, TOKEN_AS) {
            parser_next_token(p)
            cast_type := parser_parse_type(p)
            cast := ast_new(AST_CAST_EXPR, p.current_token.line, p.current_token.column)
            ast_add_child(cast, left)
            ast_add_child(cast, cast_type)
            return parser_parse_infix_expression(p, cast, precedence)
        } else {
            return left
        }
    }
    left
}
