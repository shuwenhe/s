package compile.internal.parser.syntax

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
    int* kind
    int line
    int col
    string* value
    ast_node* left
    ast_node* right
    ast_node* child
    ast_node* next
}

struct parser {
    tokens* compile.internal.parser.syntax.token
    int token_count
    int pos
}

func syntax_parser_new(tokens* compile.internal.parser.syntax.token, int token_count) parser* {
    p := alloc(compile.internal.parser.syntax.parser)
    p.tokens = tokens
    p.token_count = token_count
    p.pos = 0
    return p
}

func syntax_parser_current_token(p* parser) compile.internal.parser.syntax.token {
    if p.pos >= p.token_count {
        return p.tokens[p.token_count - 1]
    }
    return p.tokens[p.pos]
}

func syntax_parser_advance(p* parser) {
    if p.pos < p.token_count - 1 {
        p.pos = p.pos + 1
    }
}

func syntax_parser_match(p* parser, token_type token_type) int {
    if syntax_parser_current_token(p).kind == token_type {
        syntax_parser_advance(p)
        return 1
    }
    return 0
}

func syntax_parser_skip_newlines(p* parser) {
    for {
        if syntax_parser_current_token(p).kind != 86 {
            break
        }
        syntax_parser_advance(p)
    }
}

func syntax_parser_parse_program(p* parser) ast_node* {
    syntax_parser_skip_newlines(p)
    prog := alloc(compile.internal.parser.syntax.ast_node)
    prog.kind = ast_node_type.ast_program
    prog.line = syntax_parser_current_token(p).line
    prog.col = syntax_parser_current_token(p).col
    tail := prog
    for {
        if syntax_parser_current_token(p).kind == 0 {
            break
        }
        syntax_parser_skip_newlines(p)
        current := syntax_parser_current_token(p)
        if current.kind == 10 {
            func_decl := syntax_parser_parse_func_decl(p)
            if func_decl != nil { tail.next = func_decl; tail = func_decl }
        } else if current.kind == 20 {
            struct_decl := syntax_parser_parse_struct_decl(p)
            if struct_decl != nil { tail.next = struct_decl; tail = struct_decl }
        } else if current.kind == 21 {
            var_decl := syntax_parser_parse_var_decl(p)
            if var_decl != nil { tail.next = var_decl; tail = var_decl }
        } else if current.kind == 22 {
            const_decl := syntax_parser_parse_const_decl(p)
            if const_decl != nil { tail.next = const_decl; tail = const_decl }
        } else {
            syntax_parser_advance(p)
        }
    }
    return prog
}

func syntax_parser_parse_func_decl(p* parser) ast_node* {
    func_decl := alloc(compile.internal.parser.syntax.ast_node)
    func_decl.kind = ast_node_type.ast_func_decl
    func_decl.line = syntax_parser_current_token(p).line
    func_decl.col = syntax_parser_current_token(p).col
    if !syntax_parser_match(p, token_type.tok_return) {
        return nil
    }
    if syntax_parser_current_token(p).kind == 24 {
        syntax_parser_parse_receiver(p)
    }
    if syntax_parser_current_token(p).kind != 85 {
        return nil
    }
    func_decl.value = syntax_parser_current_token(p).value
    syntax_parser_advance(p)
    if syntax_parser_current_token(p).kind == 24 {
        syntax_parser_parse_params(p)
    }
    if syntax_parser_current_token(p).kind != 28 {
        func_decl.child = syntax_parser_parse_type(p)
    }
    if syntax_parser_current_token(p).kind == 28 {
        func_decl.next = syntax_parser_parse_block_stmt(p)
    }
    return func_decl
}

func syntax_parser_parse_struct_decl(p* parser) ast_node* {
    struct_decl := alloc(compile.internal.parser.syntax.ast_node)
    struct_decl.kind = ast_node_type.ast_struct_decl
    if !syntax_parser_match(p, token_type.tok_package) {
        return nil
    }
    if syntax_parser_current_token(p).kind != 85 {
        return nil
    }
    struct_decl.value = syntax_parser_current_token(p).value
    syntax_parser_advance(p)
    if syntax_parser_current_token(p).kind == 28 {
        syntax_parser_advance(p)
        for {
            syntax_parser_skip_newlines(p)
            if syntax_parser_current_token(p).kind == 29 {
                syntax_parser_advance(p)
                break
            }
            if syntax_parser_current_token(p).kind == 85 {
                syntax_parser_advance(p)
                syntax_parser_parse_type(p)
            }
            syntax_parser_skip_newlines(p)
        }
    }
    return struct_decl
}

func syntax_parser_parse_var_decl(p* parser) ast_node* {
    var_decl := alloc(compile.internal.parser.syntax.ast_node)
    var_decl.kind = ast_node_type.ast_var_decl
    if !syntax_parser_match(p, token_type.tok_type) {
        return nil
    }
    if syntax_parser_current_token(p).kind != 85 {
        return nil
    }
    var_decl.value = syntax_parser_current_token(p).value
    syntax_parser_advance(p)
    var_decl.child = syntax_parser_parse_type(p)
    if syntax_parser_current_token(p).kind == 60 {
        syntax_parser_advance(p)
        ret.child = syntax_parser_parse_expression(p)
    }
    return var_decl
}

func syntax_parser_parse_const_decl(p* parser) ast_node* {
    const_decl := alloc(compile.internal.parser.syntax.ast_node)
    const_decl.kind = ast_node_type.ast_const_decl
    if !syntax_parser_match(p, token_type.tok_defer) {
        return nil
    }
    if syntax_parser_current_token(p).kind != 85 {
        return nil
    }
    syntax_parser_advance(p)
    if syntax_parser_current_token(p).kind != 60 {
        syntax_parser_parse_type(p)
    }
    if syntax_parser_current_token(p).kind == 60 {
        syntax_parser_advance(p)
        syntax_parser_parse_expression(p)
    }
    return const_decl
}

func syntax_parser_parse_receiver(p* parser) {
    if syntax_parser_current_token(p).kind == 24 {
        syntax_parser_advance(p)
        if syntax_parser_current_token(p).kind == 85 {
            syntax_parser_advance(p)
        }
        syntax_parser_parse_type(p)
        if syntax_parser_current_token(p).kind == 25 {
            syntax_parser_advance(p)
        }
    }
}

func syntax_parser_parse_params(p* parser) {
    if syntax_parser_current_token(p).kind == 24 {
        syntax_parser_advance(p)
        for syntax_parser_current_token(p).kind != 25 {
            if syntax_parser_current_token(p).kind == 85 {
                syntax_parser_advance(p)
            }
            syntax_parser_parse_type(p)
            if syntax_parser_current_token(p).kind == 58 {
                syntax_parser_advance(p)
            } else {
                break
            }
        }
        if syntax_parser_current_token(p).kind == 25 {
            syntax_parser_advance(p)
        }
    }
}

func syntax_parser_parse_type(p* parser) ast_node* {
    type_node := alloc(compile.internal.parser.syntax.ast_node)
    current := syntax_parser_current_token(p)
    if current.kind == 52 {
        syntax_parser_advance(p)
        type_node.kind = ast_node_type.ast_pointer_type
        type_node.child = syntax_parser_parse_type(p)
        return type_node
    }
    if current.kind == 26 {
        syntax_parser_advance(p)
        type_node.kind = ast_node_type.ast_array_type
        if syntax_parser_current_token(p).kind != 27 {
            syntax_parser_parse_expression(p)
        }
        if syntax_parser_current_token(p).kind == 27 {
            syntax_parser_advance(p)
        }
        type_node.child = syntax_parser_parse_type(p)
        return type_node
    }
    if current.kind == 85 {
        type_node.value = current.value
        syntax_parser_advance(p)
    }
    return type_node
}

func syntax_parser_parse_block_stmt(p* parser) ast_node* {
    block := alloc(compile.internal.parser.syntax.ast_node)
    block.kind = ast_node_type.ast_block_stmt
    if syntax_parser_current_token(p).kind == 28 {
        syntax_parser_advance(p)
        for {
            syntax_parser_skip_newlines(p)
            if syntax_parser_current_token(p).kind == 29 {
                syntax_parser_advance(p)
                break
            }
            syntax_parser_parse_statement(p)
            syntax_parser_skip_newlines(p)
        }
    }
    return block
}

func syntax_parser_parse_statement(p* parser) ast_node* {
    current := syntax_parser_current_token(p)
    if current.kind == 11 {
        return syntax_parser_parse_return_stmt(p)
    } else if current.kind == 12 {
        return syntax_parser_parse_if_stmt(p)
    } else if current.kind == 13 {
        return syntax_parser_parse_for_stmt(p)
    } else if current.kind == 14 {
        syntax_parser_advance(p)
        stmt := alloc(compile.internal.parser.syntax.ast_node)
        stmt.kind = ast_node_type.ast_break_stmt
        return stmt
    } else if current.kind == 15 {
        syntax_parser_advance(p)
        stmt := alloc(compile.internal.parser.syntax.ast_node)
        stmt.kind = ast_node_type.ast_continue_stmt
        return stmt
    } else if current.kind == 28 {
        return syntax_parser_parse_block_stmt(p)
    } else {
        return syntax_parser_parse_expr_stmt(p)
    }
}

func syntax_parser_parse_return_stmt(p* parser) ast_node* {
    ret := alloc(compile.internal.parser.syntax.ast_node)
    ret.kind = ast_node_type.ast_return_stmt
    if syntax_parser_current_token(p).kind == 11 {
        syntax_parser_advance(p)
    }
    if syntax_parser_current_token(p).kind != 29 &&
       syntax_parser_current_token(p).kind != 86 {
        syntax_parser_parse_expression(p)
    }
    return ret
}

func syntax_parser_parse_if_stmt(p* parser) ast_node* {
    if_stmt := alloc(compile.internal.parser.syntax.ast_node)
    if_stmt.kind = ast_node_type.ast_if_stmt
    if syntax_parser_current_token(p).kind == 12 {
        syntax_parser_advance(p)
    }
    syntax_parser_parse_expression(p)
    syntax_parser_parse_block_stmt(p)
    if syntax_parser_current_token(p).kind == 16 {
        syntax_parser_advance(p)
        syntax_parser_parse_statement(p)
    }
    return if_stmt
}

func syntax_parser_parse_for_stmt(p* parser) ast_node* {
    for_stmt := alloc(compile.internal.parser.syntax.ast_node)
    for_stmt.kind = ast_node_type.ast_for_stmt
    if syntax_parser_current_token(p).kind == 13 {
        syntax_parser_advance(p)
    }
    if syntax_parser_current_token(p).kind != 28 {
        syntax_parser_parse_expression(p)
    }
    syntax_parser_parse_block_stmt(p)
    return for_stmt
}

func syntax_parser_parse_expr_stmt(p* parser) ast_node* {
    expr_stmt := alloc(compile.internal.parser.syntax.ast_node)
    expr_stmt.kind = ast_node_type.ast_expr_stmt
    syntax_parser_parse_expression(p)
    return expr_stmt
}

func syntax_parser_parse_expression(p* parser) ast_node* {
    return syntax_parser_parse_assignment(p)
}

func syntax_parser_parse_assignment(p* parser) ast_node* {
    expr := syntax_parser_parse_logical_or(p)
    if syntax_parser_current_token(p).kind == 60 {
        syntax_parser_advance(p)
        rhs := syntax_parser_parse_assignment(p)
    }
    return expr
}

func syntax_parser_parse_logical_or(p* parser) ast_node* {
    left := syntax_parser_parse_logical_and(p)
    for {
        if syntax_parser_current_token(p).kind == 74 {
            syntax_parser_advance(p)
            right := syntax_parser_parse_logical_and(p)
            expr := alloc(compile.internal.parser.syntax.ast_node)
            expr.kind = ast_node_type.ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func syntax_parser_parse_logical_and(p* parser) ast_node* {
    left := syntax_parser_parse_equality(p)
    for {
        if syntax_parser_current_token(p).kind == 73 {
            syntax_parser_advance(p)
            right := syntax_parser_parse_equality(p)
            expr := alloc(compile.internal.parser.syntax.ast_node)
            expr.kind = ast_node_type.ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func syntax_parser_parse_equality(p* parser) ast_node* {
    left := syntax_parser_parse_comparison(p)
    for {
        current_type := syntax_parser_current_token(p).kind
        if current_type == 62 || current_type == 63 {
            syntax_parser_advance(p)
            right := syntax_parser_parse_comparison(p)
            expr := alloc(compile.internal.parser.syntax.ast_node)
            expr.kind = ast_node_type.ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func syntax_parser_parse_comparison(p* parser) ast_node* {
    left := syntax_parser_parse_additive(p)
    for {
        current_type := syntax_parser_current_token(p).kind
        if current_type == 64 || current_type == 65 ||
           current_type == 66 || current_type == 67 {
            syntax_parser_advance(p)
            right := syntax_parser_parse_additive(p)
            expr := alloc(compile.internal.parser.syntax.ast_node)
            expr.kind = ast_node_type.ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func syntax_parser_parse_additive(p* parser) ast_node* {
    left := syntax_parser_parse_multiplicative(p)
    for {
        if syntax_parser_current_token(p).kind == 53 || syntax_parser_current_token(p).kind == 54 {
            syntax_parser_advance(p)
            right := syntax_parser_parse_multiplicative(p)
            expr := alloc(compile.internal.parser.syntax.ast_node)
            expr.kind = ast_node_type.ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func syntax_parser_parse_multiplicative(p* parser) ast_node* {
    left := syntax_parser_parse_unary(p)
    for {
        current_type := syntax_parser_current_token(p).kind
        if current_type == 55 || current_type == 56 || current_type == 57 {
            syntax_parser_advance(p)
            right := syntax_parser_parse_unary(p)
            expr := alloc(compile.internal.parser.syntax.ast_node)
            expr.kind = ast_node_type.ast_binary_expr
            expr.left = left
            expr.right = right
            left = expr
        } else {
            break
        }
    }
    return left
}

func syntax_parser_parse_unary(p* parser) ast_node* {
    current_type := syntax_parser_current_token(p).kind
    if current_type == 54 || current_type == 52 || current_type == 75 {
        syntax_parser_advance(p)
        unary := alloc(compile.internal.parser.syntax.ast_node)
        unary.kind = ast_node_type.ast_unary_expr
        unary.child = syntax_parser_parse_unary(p)
        return unary
    }
    return syntax_parser_parse_postfix(p)
}

func syntax_parser_parse_postfix(p* parser) ast_node* {
    left := syntax_parser_parse_primary(p)
    for {
        if syntax_parser_current_token(p).kind == 24 {
            syntax_parser_advance(p)
            call := alloc(compile.internal.parser.syntax.ast_node)
            call.kind = ast_node_type.ast_call_expr
            for syntax_parser_current_token(p).kind != 25 {
                syntax_parser_parse_expression(p)
                if syntax_parser_current_token(p).kind == 58 {
                    syntax_parser_advance(p)
                } else {
                    break
                }
            }
            if syntax_parser_current_token(p).kind == 25 {
                syntax_parser_advance(p)
            }
            left = call
        } else if syntax_parser_current_token(p).kind == 26 {
            syntax_parser_advance(p)
            index := alloc(compile.internal.parser.syntax.ast_node)
            index.kind = ast_node_type.ast_index_expr
            syntax_parser_parse_expression(p)
            if syntax_parser_current_token(p).kind == 27 {
                syntax_parser_advance(p)
            }
            left = index
        } else if syntax_parser_current_token(p).kind == 59 {
            syntax_parser_advance(p)
            member := alloc(compile.internal.parser.syntax.ast_node)
            member.kind = ast_node_type.ast_member_expr
            if syntax_parser_current_token(p).kind == 85 {
                syntax_parser_advance(p)
            }
            left = member
        } else {
            break
        }
    }
    return left
}

func syntax_parser_parse_primary(p* parser) ast_node* {
    current := syntax_parser_current_token(p)
    primary := alloc(compile.internal.parser.syntax.ast_node)
    if current.kind == 85 {
        primary.kind = ast_node_type.ast_ident_expr
        primary.value = current.value
        syntax_parser_advance(p)
    } else if current.kind == 80 || current.kind == 81 || current.kind == 82 ||
              current.kind == 83 || current.kind == 84 {
        primary.kind = ast_node_type.ast_literal_expr
        primary.value = current.value
        syntax_parser_advance(p)
    } else if current.kind == 24 {
        syntax_parser_advance(p)
        primary.kind = ast_node_type.ast_paren_expr
        primary.child = syntax_parser_parse_expression(p)
        if syntax_parser_current_token(p).kind == 25 {
            syntax_parser_advance(p)
        }
    }
    return primary
}
