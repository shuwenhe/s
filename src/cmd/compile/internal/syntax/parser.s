package compile.internal.syntax
enum ast_node_type {
    ast_program = 1,
    ast_package = 2,
    ast_import = 3,
    ast_func_decl = 4,
    ast_func_type = 5,
    ast_struct_decl = 6,
    ast_interface_decl = 7,
    ast_var_decl = 8,
    ast_const_decl = 9,
    ast_type_decl = 10,
    ast_block_stmt = 20,
    ast_expr_stmt = 21,
    ast_return_stmt = 22,
    ast_if_stmt = 23,
    ast_for_stmt = 24,
    ast_break_stmt = 25,
    ast_continue_stmt = 26,
    ast_switch_stmt = 27,
    ast_defer_stmt = 28,
    ast_binary_expr = 40,
    ast_unary_expr = 41,
    ast_call_expr = 42,
    ast_index_expr = 43,
    ast_slice_expr = 44,
    ast_member_expr = 45,
    ast_ident_expr = 46,
    ast_literal_expr = 47,
    ast_paren_expr = 48,
    ast_array_type = 49,
    ast_map_type = 50,
    ast_chan_type = 51,
    ast_pointer_type = 52,
}
struct ast_node {
    type_* int
    line int
    col int
    value* string
    left* ast_node
    right* ast_node
    child* ast_node
    next* ast_node
}

struct parser {
    tokens* token
    token_count int
    pos int
}

func parser_new(tokens* token, int token_count) parser* {
    p := alloc(parser)
    p.tokens = tokens
    p.token_count = token_count
    p.pos = 0
    return p
}

func parser_current_token(p* parser) token* {
    if p.pos >= p.token_count {
        return &p.tokens[p.token_count - 1]
    }
    return &p.tokens[p.pos]
}

func parser_advance(p* parser) {
    if p.pos < p.token_count - 1 {
        p.pos = p.pos + 1
    }
}

func parser_match(p* parser, int token_type) int {
    if parser_current_token(p).type_ == token_type {
        parser_advance(p)
        return 1
    }
    return 0
}

func parser_skip_newlines(p* parser) {
    for {
        if parser_current_token(p).type_ != 86 {
            break
        }
        parser_advance(p)
    }
}

func parser_parse_program(p* parser) ast_node* {
    parser_skip_newlines(p)
    prog := alloc(ast_node)
    prog.type_ = ast_program
    prog.line = parser_current_token(p).line
    prog.col = parser_current_token(p).col
    tail := prog
    for {
        if parser_current_token(p).type_ == 0 {
            break
        }
        parser_skip_newlines(p)
        current := parser_current_token(p)
        if current.type_ == 10 {
            func_decl := parser_parse_func_decl(p)
            if func_decl != nil { tail.next = func_decl; tail = func_decl }
        } else if current.type_ == 20 {
            struct_decl := parser_parse_struct_decl(p)
            if struct_decl != nil { tail.next = struct_decl; tail = struct_decl }
        } else if current.type_ == 21 {
            var_decl := parser_parse_var_decl(p)
            if var_decl != nil { tail.next = var_decl; tail = var_decl }
        } else if current.type_ == 22 {
            const_decl := parser_parse_const_decl(p)
            if const_decl != nil { tail.next = const_decl; tail = const_decl }
        } else {
            parser_advance(p)
        }
    }
    return prog
}

func parser_parse_func_decl(p* parser) ast_node* {
    func_decl := alloc(ast_node)
    func_decl.type_ = ast_func_decl
    func_decl.line = parser_current_token(p).line
    func_decl.col = parser_current_token(p).col
    if !parser_match(p, 10) {
        return nil
    }
    if parser_current_token(p).type_ == 24 {
        parser_parse_receiver(p)
    }
    if parser_current_token(p).type_ != 85 {
        return nil
    }
    func_decl.value = parser_current_token(p).value
    parser_advance(p)
    if parser_current_token(p).type_ == 24 {
        parser_parse_params(p)
    }
    if parser_current_token(p).type_ != 28 {
        func_decl.child = parser_parse_type(p)
    }
    if parser_current_token(p).type_ == 28 {
        func_decl.next = parser_parse_block_stmt(p)
    }
    return func_decl
}

func parser_parse_struct_decl(p* parser) ast_node* {
    struct_decl := alloc(ast_node)
    struct_decl.type_ = ast_struct_decl
    if !parser_match(p, 20) {
        return nil
    }
    if parser_current_token(p).type_ != 85 {
        return nil
    }
    struct_decl.value = parser_current_token(p).value
    parser_advance(p)
    if parser_current_token(p).type_ == 28 {
        parser_advance(p)
        for {
            parser_skip_newlines(p)
            if parser_current_token(p).type_ == 29 {
                parser_advance(p)
                break
            }
            if parser_current_token(p).type_ == 85 {
                parser_advance(p)
                parser_parse_type(p)
            }
            parser_skip_newlines(p)
        }
    }
    return struct_decl
}

func parser_parse_var_decl(p* parser) ast_node* {
    var_decl := alloc(ast_node)
    var_decl.type_ = ast_var_decl
    if !parser_match(p, 21) {
        return nil
    }
    if parser_current_token(p).type_ != 85 {
        return nil
    }
    var_decl.value = parser_current_token(p).value
    parser_advance(p)
    var_decl.child = parser_parse_type(p)
    if parser_current_token(p).type_ == 60 {
        parser_advance(p)
        ret.child = parser_parse_expression(p)
    }
    return var_decl
}

func parser_parse_const_decl(p* parser) ast_node* {
    const_decl := alloc(ast_node)
    const_decl.type_ = ast_const_decl
    if !parser_match(p, 22) {
        return nil
    }
    if parser_current_token(p).type_ != 85 {
        return nil
    }
    parser_advance(p)
    if parser_current_token(p).type_ != 60 {
        parser_parse_type(p)
    }
    if parser_current_token(p).type_ == 60 {
        parser_advance(p)
        parser_parse_expression(p)
    }
    return const_decl
}

func parser_parse_receiver(p* parser) {
    if parser_current_token(p).type_ == 24 {
        parser_advance(p)
        if parser_current_token(p).type_ == 85 {
            parser_advance(p)
        }
        parser_parse_type(p)
        if parser_current_token(p).type_ == 25 {
            parser_advance(p)
        }
    }
}

func parser_parse_params(p* parser) {
    if parser_current_token(p).type_ == 24 {
        parser_advance(p)
        for parser_current_token(p).type_ != 25 {
            if parser_current_token(p).type_ == 85 {
                parser_advance(p)
            }
            parser_parse_type(p)
            if parser_current_token(p).type_ == 58 {
                parser_advance(p)
            } else {
                break
            }
        }
        if parser_current_token(p).type_ == 25 {
            parser_advance(p)
        }
    }
}

func parser_parse_type(p* parser) ast_node* {
    type_node := alloc(ast_node)
    current := parser_current_token(p)
    if current.type_ == 52 {
        parser_advance(p)
        type_node.type_ = ast_pointer_type
        type_node.child = parser_parse_type(p)
        return type_node
    }
    if current.type_ == 26 {
        parser_advance(p)
        type_node.type_ = ast_array_type
        if parser_current_token(p).type_ != 27 {
            parser_parse_expression(p)
        }
        if parser_current_token(p).type_ == 27 {
            parser_advance(p)
        }
        type_node.child = parser_parse_type(p)
        return type_node
    }
    if current.type_ == 85 {
        type_node.value = current.value
        parser_advance(p)
    }
    return type_node
}

func parser_parse_block_stmt(p* parser) ast_node* {
    block := alloc(ast_node)
    block.type_ = ast_block_stmt
    if parser_current_token(p).type_ == 28 {
        parser_advance(p)
        for {
            parser_skip_newlines(p)
            if parser_current_token(p).type_ == 29 {
                parser_advance(p)
                break
            }
            parser_parse_statement(p)
            parser_skip_newlines(p)
        }
    }
    return block
}

func parser_parse_statement(p* parser) ast_node* {
    current := parser_current_token(p)
    if current.type_ == 11 {
        return parser_parse_return_stmt(p)
    } else if current.type_ == 12 {
        return parser_parse_if_stmt(p)
    } else if current.type_ == 13 {
        return parser_parse_for_stmt(p)
    } else if current.type_ == 14 {
        parser_advance(p)
        stmt := alloc(ast_node)
        stmt.type_ = ast_break_stmt
        return stmt
    } else if current.type_ == 15 {
        parser_advance(p)
        stmt := alloc(ast_node)
        stmt.type_ = ast_continue_stmt
        return stmt
    } else if current.type_ == 28 {
        return parser_parse_block_stmt(p)
    } else {
        return parser_parse_expr_stmt(p)
    }
}

func parser_parse_return_stmt(p* parser) ast_node* {
    ret := alloc(ast_node)
    ret.type_ = ast_return_stmt
    if parser_current_token(p).type_ == 11 {
        parser_advance(p)
    }
    if parser_current_token(p).type_ != 29 &&
       parser_current_token(p).type_ != 86 {
        parser_parse_expression(p)
    }
    return ret
}

func parser_parse_if_stmt(p* parser) ast_node* {
    if_stmt := alloc(ast_node)
    if_stmt.type_ = ast_if_stmt
    if parser_current_token(p).type_ == 12 {
        parser_advance(p)
    }
    parser_parse_expression(p)
    parser_parse_block_stmt(p)
    if parser_current_token(p).type_ == 16 {
        parser_advance(p)
        parser_parse_statement(p)
    }
    return if_stmt
}

func parser_parse_for_stmt(p* parser) ast_node* {
    for_stmt := alloc(ast_node)
    for_stmt.type_ = ast_for_stmt
    if parser_current_token(p).type_ == 13 {
        parser_advance(p)
    }
    if parser_current_token(p).type_ != 28 {
        parser_parse_expression(p)
    }
    parser_parse_block_stmt(p)
    return for_stmt
}

func parser_parse_expr_stmt(p* parser) ast_node* {
    expr_stmt := alloc(ast_node)
    expr_stmt.type_ = ast_expr_stmt
    parser_parse_expression(p)
    return expr_stmt
}

func parser_parse_expression(p* parser) ast_node* {
    return parser_parse_assignment(p)
}

func parser_parse_assignment(p* parser) ast_node* {
    expr := parser_parse_logical_or(p)
    if parser_current_token(p).type_ == 60 {
        parser_advance(p)
        rhs := parser_parse_assignment(p)
    }
    return expr
}

func parser_parse_logical_or(p* parser) ast_node* {
    left := parser_parse_logical_and(p)
    for {
        if parser_current_token(p).type_ == 74 {
            parser_advance(p)
            right := parser_parse_logical_and(p)
            expr := alloc(ast_node)
            expr.type_ = ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func parser_parse_logical_and(p* parser) ast_node* {
    left := parser_parse_equality(p)
    for {
        if parser_current_token(p).type_ == 73 {
            parser_advance(p)
            right := parser_parse_equality(p)
            expr := alloc(ast_node)
            expr.type_ = ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func parser_parse_equality(p* parser) ast_node* {
    left := parser_parse_comparison(p)
    for {
        current_type := parser_current_token(p).type_
        if current_type == 62 || current_type == 63 {
            parser_advance(p)
            right := parser_parse_comparison(p)
            expr := alloc(ast_node)
            expr.type_ = ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func parser_parse_comparison(p* parser) ast_node* {
    left := parser_parse_additive(p)
    for {
        current_type := parser_current_token(p).type_
        if current_type == 64 || current_type == 65 ||
           current_type == 66 || current_type == 67 {
            parser_advance(p)
            right := parser_parse_additive(p)
            expr := alloc(ast_node)
            expr.type_ = ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func parser_parse_additive(p* parser) ast_node* {
    left := parser_parse_multiplicative(p)
    for {
        if parser_current_token(p).type_ == 53 || parser_current_token(p).type_ == 54 {
            parser_advance(p)
            right := parser_parse_multiplicative(p)
            expr := alloc(ast_node)
            expr.type_ = ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func parser_parse_multiplicative(p* parser) ast_node* {
    left := parser_parse_unary(p)
    for {
        current_type := parser_current_token(p).type_
        if current_type == 55 || current_type == 56 || current_type == 57 {
            parser_advance(p)
            right := parser_parse_unary(p)
            expr := alloc(ast_node)
            expr.type_ = ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func parser_parse_unary(p* parser) ast_node* {
    current_type := parser_current_token(p).type_
    if current_type == 54 || current_type == 52 || current_type == 75 {
        parser_advance(p)
        unary := alloc(ast_node)
        unary.type_ = ast_unary_expr
        unary.child = parser_parse_unary(p)
        return unary
    }
    return parser_parse_postfix(p)
}

func parser_parse_postfix(p* parser) ast_node* {
    left := parser_parse_primary(p)
    for {
        if parser_current_token(p).type_ == 24 {
            parser_advance(p)
            call := alloc(ast_node)
            call.type_ = ast_call_expr
            for parser_current_token(p).type_ != 25 {
                parser_parse_expression(p)
                if parser_current_token(p).type_ == 58 {
                    parser_advance(p)
                } else {
                    break
                }
            }
            if parser_current_token(p).type_ == 25 {
                parser_advance(p)
            }
            left = call
        } else if parser_current_token(p).type_ == 26 {
            parser_advance(p)
            index := alloc(ast_node)
            index.type_ = ast_index_expr
            parser_parse_expression(p)
            if parser_current_token(p).type_ == 27 {
                parser_advance(p)
            }
            left = index
        } else if parser_current_token(p).type_ == 59 {
            parser_advance(p)
            member := alloc(ast_node)
            member.type_ = ast_member_expr
            if parser_current_token(p).type_ == 85 {
                parser_advance(p)
            }
            left = member
        } else {
            break
        }
    }
    return left
}

func parser_parse_primary(p* parser) ast_node* {
    current := parser_current_token(p)
    primary := alloc(ast_node)
    if current.type_ == 85 {
        primary.type_ = ast_ident_expr
        primary.value = current.value
        parser_advance(p)
    } else if current.type_ == 80 || current.type_ == 81 || current.type_ == 82 ||
              current.type_ == 83 || current.type_ == 84 {
        primary.type_ = ast_literal_expr
        primary.value = current.value
        parser_advance(p)
    } else if current.type_ == 24 {
        parser_advance(p)
        primary.type_ = ast_paren_expr
        primary.child = parser_parse_expression(p)
        if parser_current_token(p).type_ == 25 {
            parser_advance(p)
        }
    }
    return primary
}
