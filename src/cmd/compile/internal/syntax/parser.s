// S 语言语法分析器 (Parser)
// 将 Token 流转换为 AST (抽象语法树)

package compile.internal.syntax

// AST 节点类型
enum ast_node_type {
    AST_PROGRAM = 1,       // 程序
    AST_PACKAGE = 2,       // 包声明
    AST_IMPORT = 3,        // 导入声明
    AST_FUNC_DECL = 4,     // 函数声明
    AST_FUNC_TYPE = 5,     // 函数类型
    AST_STRUCT_DECL = 6,   // 结构体声明
    AST_INTERFACE_DECL = 7, // 接口声明
    AST_VAR_DECL = 8,      // 变量声明
    AST_CONST_DECL = 9,    // 常量声明
    AST_TYPE_DECL = 10,    // 类型声明
    
    AST_BLOCK_STMT = 20,   // 块语句
    AST_EXPR_STMT = 21,    // 表达式语句
    AST_RETURN_STMT = 22,  // return 语句
    AST_IF_STMT = 23,      // if 语句
    AST_FOR_STMT = 24,     // for 语句
    AST_BREAK_STMT = 25,   // break 语句
    AST_CONTINUE_STMT = 26, // continue 语句
    AST_SWITCH_STMT = 27,  // switch 语句
    AST_DEFER_STMT = 28,   // defer 语句
    
    AST_BINARY_EXPR = 40,  // 二元表达式
    AST_UNARY_EXPR = 41,   // 一元表达式
    AST_CALL_EXPR = 42,    // 函数调用表达式
    AST_INDEX_EXPR = 43,   // 索引表达式
    AST_SLICE_EXPR = 44,   // 切片表达式
    AST_MEMBER_EXPR = 45,  // 成员访问表达式
    AST_IDENT_EXPR = 46,   // 标识符表达式
    AST_LITERAL_EXPR = 47, // 字面量表达式
    AST_PAREN_EXPR = 48,   // 括号表达式
    AST_ARRAY_TYPE = 49,   // 数组类型
    AST_MAP_TYPE = 50,     // Map 类型
    AST_CHAN_TYPE = 51,    // Channel 类型
    AST_POINTER_TYPE = 52, // 指针类型
}

// 基础 AST 节点
struct ast_node {
    type_* int
    line int
    col int
}

// Parser 结构体
struct parser {
    tokens* token
    token_count int
    pos int            // 当前 Token 位置
}

// 创建新 Parser
func parser_new(tokens* token, token_count int) parser* {
    p* := alloc(parser)
    p.tokens = tokens
    p.token_count = token_count
    p.pos = 0
    return p
}

// 获取当前 Token
func parser_current_token(p* parser) token* {
    if p.pos >= p.token_count {
        return &p.tokens[p.token_count - 1]  // 返回 EOF
    }
    return &p.tokens[p.pos]
}

// 推进到下一个 Token
func parser_advance(p* parser) {
    if p.pos < p.token_count - 1 {
        p.pos = p.pos + 1
    }
}

// 匹配 Token 类型
func parser_match(p* parser, token_type int) int {
    if parser_current_token(p).type_ == token_type {
        parser_advance(p)
        return 1
    }
    return 0
}

// 跳过换行符
func parser_skip_newlines(p* parser) {
    for {
        if parser_current_token(p).type_ != 86 {  // TOK_NEWLINE
            break
        }
        parser_advance(p)
    }
}

// 解析程序
func parser_parse_program(p* parser) ast_node* {
    parser_skip_newlines(p)
    
    prog* := alloc(ast_node)
    prog.type_ = AST_PROGRAM
    prog.line = parser_current_token(p).line
    prog.col = parser_current_token(p).col
    
    // 解析所有顶级声明
    for {
        if parser_current_token(p).type_ == 0 {  // TOK_EOF
            break
        }
        
        parser_skip_newlines(p)
        
        // 识别声明类型
        current* := parser_current_token(p)
        if current.type_ == 10 {  // TOK_FUNC
            // 函数声明
            func_decl* := parser_parse_func_decl(p)
        } else if current.type_ == 20 {  // TOK_STRUCT
            // 结构体声明
            struct_decl* := parser_parse_struct_decl(p)
        } else if current.type_ == 21 {  // TOK_VAR
            // 变量声明
            var_decl* := parser_parse_var_decl(p)
        } else if current.type_ == 22 {  // TOK_CONST
            // 常量声明
            const_decl* := parser_parse_const_decl(p)
        } else {
            parser_advance(p)
        }
    }
    
    return prog
}

// 解析函数声明
func parser_parse_func_decl(p* parser) ast_node* {
    func_decl* := alloc(ast_node)
    func_decl.type_ = AST_FUNC_DECL
    func_decl.line = parser_current_token(p).line
    func_decl.col = parser_current_token(p).col
    
    // func 关键字
    if !parser_match(p, 10) {  // TOK_FUNC
        return nil
    }
    
    // 方法接收者 (可选)
    if parser_current_token(p).type_ == 24 {  // TOK_LPAREN
        parser_parse_receiver(p)
    }
    
    // 函数名
    if parser_current_token(p).type_ != 85 {  // TOK_IDENT
        return nil
    }
    parser_advance(p)
    
    // 参数列表
    if parser_current_token(p).type_ == 24 {  // TOK_LPAREN
        parser_parse_params(p)
    }
    
    // 返回类型 (可选)
    if parser_current_token(p).type_ != 28 {  // TOK_LBRACE
        parser_parse_type(p)
    }
    
    // 函数体
    if parser_current_token(p).type_ == 28 {  // TOK_LBRACE
        parser_parse_block_stmt(p)
    }
    
    return func_decl
}

// 解析结构体声明
func parser_parse_struct_decl(p* parser) ast_node* {
    struct_decl* := alloc(ast_node)
    struct_decl.type_ = AST_STRUCT_DECL
    
    // struct 关键字
    if !parser_match(p, 20) {  // TOK_STRUCT
        return nil
    }
    
    // 结构体名
    if parser_current_token(p).type_ != 85 {  // TOK_IDENT
        return nil
    }
    parser_advance(p)
    
    // 结构体体
    if parser_current_token(p).type_ == 28 {  // TOK_LBRACE
        parser_advance(p)
        
        for {
            parser_skip_newlines(p)
            
            if parser_current_token(p).type_ == 29 {  // TOK_RBRACE
                parser_advance(p)
                break
            }
            
            // 字段定义
            if parser_current_token(p).type_ == 85 {  // TOK_IDENT
                parser_advance(p)
                parser_parse_type(p)
            }
            
            parser_skip_newlines(p)
        }
    }
    
    return struct_decl
}

// 解析变量声明
func parser_parse_var_decl(p* parser) ast_node* {
    var_decl* := alloc(ast_node)
    var_decl.type_ = AST_VAR_DECL
    
    // var 关键字
    if !parser_match(p, 21) {  // TOK_VAR
        return nil
    }
    
    // 变量名
    if parser_current_token(p).type_ != 85 {  // TOK_IDENT
        return nil
    }
    parser_advance(p)
    
    // 类型
    parser_parse_type(p)
    
    // 初始值 (可选)
    if parser_current_token(p).type_ == 60 {  // TOK_ASSIGN
        parser_advance(p)
        parser_parse_expression(p)
    }
    
    return var_decl
}

// 解析常量声明
func parser_parse_const_decl(p* parser) ast_node* {
    const_decl* := alloc(ast_node)
    const_decl.type_ = AST_CONST_DECL
    
    // const 关键字
    if !parser_match(p, 22) {  // TOK_CONST
        return nil
    }
    
    // 常量名
    if parser_current_token(p).type_ != 85 {  // TOK_IDENT
        return nil
    }
    parser_advance(p)
    
    // 类型 (可选)
    if parser_current_token(p).type_ != 60 {  // TOK_ASSIGN
        parser_parse_type(p)
    }
    
    // 初始值
    if parser_current_token(p).type_ == 60 {  // TOK_ASSIGN
        parser_advance(p)
        parser_parse_expression(p)
    }
    
    return const_decl
}

// 解析接收者
func parser_parse_receiver(p* parser) {
    if parser_current_token(p).type_ == 24 {  // TOK_LPAREN
        parser_advance(p)
        
        if parser_current_token(p).type_ == 85 {  // TOK_IDENT
            parser_advance(p)
        }
        
        parser_parse_type(p)
        
        if parser_current_token(p).type_ == 25 {  // TOK_RPAREN
            parser_advance(p)
        }
    }
}

// 解析参数列表
func parser_parse_params(p* parser) {
    if parser_current_token(p).type_ == 24 {  // TOK_LPAREN
        parser_advance(p)
        
        while parser_current_token(p).type_ != 25 {  // TOK_RPAREN
            if parser_current_token(p).type_ == 85 {  // TOK_IDENT
                parser_advance(p)
            }
            parser_parse_type(p)
            
            if parser_current_token(p).type_ == 58 {  // TOK_COMMA
                parser_advance(p)
            } else {
                break
            }
        }
        
        if parser_current_token(p).type_ == 25 {  // TOK_RPAREN
            parser_advance(p)
        }
    }
}

// 解析类型
func parser_parse_type(p* parser) ast_node* {
    type_node* := alloc(ast_node)
    
    current* := parser_current_token(p)
    
    // 指针类型
    if current.type_ == 52 {  // TOK_STAR
        parser_advance(p)
        type_node.type_ = AST_POINTER_TYPE
        parser_parse_type(p)
        return type_node
    }
    
    // 数组类型
    if current.type_ == 26 {  // TOK_LBRACKET
        parser_advance(p)
        type_node.type_ = AST_ARRAY_TYPE
        
        if parser_current_token(p).type_ != 27 {  // TOK_RBRACKET
            parser_parse_expression(p)
        }
        
        if parser_current_token(p).type_ == 27 {  // TOK_RBRACKET
            parser_advance(p)
        }
        
        parser_parse_type(p)
        return type_node
    }
    
    // 基础类型标识符
    if current.type_ == 85 {  // TOK_IDENT
        parser_advance(p)
    }
    
    return type_node
}

// 解析块语句
func parser_parse_block_stmt(p* parser) ast_node* {
    block* := alloc(ast_node)
    block.type_ = AST_BLOCK_STMT
    
    if parser_current_token(p).type_ == 28 {  // TOK_LBRACE
        parser_advance(p)
        
        for {
            parser_skip_newlines(p)
            
            if parser_current_token(p).type_ == 29 {  // TOK_RBRACE
                parser_advance(p)
                break
            }
            
            parser_parse_statement(p)
            parser_skip_newlines(p)
        }
    }
    
    return block
}

// 解析语句
func parser_parse_statement(p* parser) ast_node* {
    current* := parser_current_token(p)
    
    if current.type_ == 11 {  // TOK_RETURN
        return parser_parse_return_stmt(p)
    } else if current.type_ == 12 {  // TOK_IF
        return parser_parse_if_stmt(p)
    } else if current.type_ == 13 {  // TOK_FOR
        return parser_parse_for_stmt(p)
    } else if current.type_ == 14 {  // TOK_BREAK
        parser_advance(p)
        stmt* := alloc(ast_node)
        stmt.type_ = AST_BREAK_STMT
        return stmt
    } else if current.type_ == 15 {  // TOK_CONTINUE
        parser_advance(p)
        stmt* := alloc(ast_node)
        stmt.type_ = AST_CONTINUE_STMT
        return stmt
    } else if current.type_ == 28 {  // TOK_LBRACE
        return parser_parse_block_stmt(p)
    } else {
        return parser_parse_expr_stmt(p)
    }
}

// 解析 return 语句
func parser_parse_return_stmt(p* parser) ast_node* {
    ret* := alloc(ast_node)
    ret.type_ = AST_RETURN_STMT
    
    if parser_current_token(p).type_ == 11 {  // TOK_RETURN
        parser_advance(p)
    }
    
    if parser_current_token(p).type_ != 29 &&  // TOK_RBRACE
       parser_current_token(p).type_ != 86 {   // TOK_NEWLINE
        parser_parse_expression(p)
    }
    
    return ret
}

// 解析 if 语句
func parser_parse_if_stmt(p* parser) ast_node* {
    if_stmt* := alloc(ast_node)
    if_stmt.type_ = AST_IF_STMT
    
    if parser_current_token(p).type_ == 12 {  // TOK_IF
        parser_advance(p)
    }
    
    // 条件表达式
    parser_parse_expression(p)
    
    // if 体
    parser_parse_block_stmt(p)
    
    // else 子句 (可选)
    if parser_current_token(p).type_ == 16 {  // TOK_ELSE
        parser_advance(p)
        parser_parse_statement(p)
    }
    
    return if_stmt
}

// 解析 for 语句
func parser_parse_for_stmt(p* parser) ast_node* {
    for_stmt* := alloc(ast_node)
    for_stmt.type_ = AST_FOR_STMT
    
    if parser_current_token(p).type_ == 13 {  // TOK_FOR
        parser_advance(p)
    }
    
    // 初始化 (可选)
    if parser_current_token(p).type_ != 28 {  // TOK_LBRACE
        parser_parse_expression(p)
    }
    
    // for 体
    parser_parse_block_stmt(p)
    
    return for_stmt
}

// 解析表达式语句
func parser_parse_expr_stmt(p* parser) ast_node* {
    expr_stmt* := alloc(ast_node)
    expr_stmt.type_ = AST_EXPR_STMT
    
    parser_parse_expression(p)
    
    return expr_stmt
}

// 解析表达式
func parser_parse_expression(p* parser) ast_node* {
    return parser_parse_assignment(p)
}

// 解析赋值表达式
func parser_parse_assignment(p* parser) ast_node* {
    expr* := parser_parse_logical_or(p)
    
    if parser_current_token(p).type_ == 60 {  // TOK_ASSIGN
        parser_advance(p)
        rhs* := parser_parse_assignment(p)
    }
    
    return expr
}

// 解析逻辑或表达式
func parser_parse_logical_or(p* parser) ast_node* {
    left* := parser_parse_logical_and(p)
    
    for {
        if parser_current_token(p).type_ == 74 {  // TOK_OR
            parser_advance(p)
            right* := parser_parse_logical_and(p)
            
            expr* := alloc(ast_node)
            expr.type_ = AST_BINARY_EXPR
            left = expr
        } else {
            break
        }
    }
    
    return left
}

// 解析逻辑与表达式
func parser_parse_logical_and(p* parser) ast_node* {
    left* := parser_parse_equality(p)
    
    for {
        if parser_current_token(p).type_ == 73 {  // TOK_AND
            parser_advance(p)
            right* := parser_parse_equality(p)
            
            expr* := alloc(ast_node)
            expr.type_ = AST_BINARY_EXPR
            left = expr
        } else {
            break
        }
    }
    
    return left
}

// 解析相等性比较
func parser_parse_equality(p* parser) ast_node* {
    left* := parser_parse_comparison(p)
    
    for {
        current_type := parser_current_token(p).type_
        if current_type == 62 || current_type == 63 {  // TOK_EQ, TOK_NE
            parser_advance(p)
            right* := parser_parse_comparison(p)
            
            expr* := alloc(ast_node)
            expr.type_ = AST_BINARY_EXPR
            left = expr
        } else {
            break
        }
    }
    
    return left
}

// 解析比较表达式
func parser_parse_comparison(p* parser) ast_node* {
    left* := parser_parse_additive(p)
    
    for {
        current_type := parser_current_token(p).type_
        if current_type == 64 || current_type == 65 || 
           current_type == 66 || current_type == 67 {  // TOK_LT, TOK_LE, TOK_GT, TOK_GE
            parser_advance(p)
            right* := parser_parse_additive(p)
            
            expr* := alloc(ast_node)
            expr.type_ = AST_BINARY_EXPR
            left = expr
        } else {
            break
        }
    }
    
    return left
}

// 解析加减法表达式
func parser_parse_additive(p* parser) ast_node* {
    left* := parser_parse_multiplicative(p)
    
    for {
        if parser_current_token(p).type_ == 53 || parser_current_token(p).type_ == 54 {  // TOK_PLUS, TOK_MINUS
            parser_advance(p)
            right* := parser_parse_multiplicative(p)
            
            expr* := alloc(ast_node)
            expr.type_ = AST_BINARY_EXPR
            left = expr
        } else {
            break
        }
    }
    
    return left
}

// 解析乘除法表达式
func parser_parse_multiplicative(p* parser) ast_node* {
    left* := parser_parse_unary(p)
    
    for {
        current_type := parser_current_token(p).type_
        if current_type == 55 || current_type == 56 || current_type == 57 {  // TOK_STAR, TOK_SLASH, TOK_PERCENT
            parser_advance(p)
            right* := parser_parse_unary(p)
            
            expr* := alloc(ast_node)
            expr.type_ = AST_BINARY_EXPR
            left = expr
        } else {
            break
        }
    }
    
    return left
}

// 解析一元表达式
func parser_parse_unary(p* parser) ast_node* {
    current_type := parser_current_token(p).type_
    
    if current_type == 54 || current_type == 52 || current_type == 75 {  // TOK_MINUS, TOK_STAR, TOK_NOT
        parser_advance(p)
        
        unary* := alloc(ast_node)
        unary.type_ = AST_UNARY_EXPR
        parser_parse_unary(p)
        return unary
    }
    
    return parser_parse_postfix(p)
}

// 解析后缀表达式
func parser_parse_postfix(p* parser) ast_node* {
    left* := parser_parse_primary(p)
    
    for {
        if parser_current_token(p).type_ == 24 {  // TOK_LPAREN (函数调用)
            parser_advance(p)
            
            call* := alloc(ast_node)
            call.type_ = AST_CALL_EXPR
            
            while parser_current_token(p).type_ != 25 {  // TOK_RPAREN
                parser_parse_expression(p)
                
                if parser_current_token(p).type_ == 58 {  // TOK_COMMA
                    parser_advance(p)
                } else {
                    break
                }
            }
            
            if parser_current_token(p).type_ == 25 {  // TOK_RPAREN
                parser_advance(p)
            }
            
            left = call
        } else if parser_current_token(p).type_ == 26 {  // TOK_LBRACKET (索引)
            parser_advance(p)
            
            index* := alloc(ast_node)
            index.type_ = AST_INDEX_EXPR
            
            parser_parse_expression(p)
            
            if parser_current_token(p).type_ == 27 {  // TOK_RBRACKET
                parser_advance(p)
            }
            
            left = index
        } else if parser_current_token(p).type_ == 59 {  // TOK_DOT (成员访问)
            parser_advance(p)
            
            member* := alloc(ast_node)
            member.type_ = AST_MEMBER_EXPR
            
            if parser_current_token(p).type_ == 85 {  // TOK_IDENT
                parser_advance(p)
            }
            
            left = member
        } else {
            break
        }
    }
    
    return left
}

// 解析基础表达式
func parser_parse_primary(p* parser) ast_node* {
    current* := parser_current_token(p)
    primary* := alloc(ast_node)
    
    if current.type_ == 85 {  // TOK_IDENT
        primary.type_ = AST_IDENT_EXPR
        parser_advance(p)
    } else if current.type_ == 80 || current.type_ == 81 || current.type_ == 82 ||
              current.type_ == 83 || current.type_ == 84 {  // 数字、字符串等字面量
        primary.type_ = AST_LITERAL_EXPR
        parser_advance(p)
    } else if current.type_ == 24 {  // TOK_LPAREN
        parser_advance(p)
        primary.type_ = AST_PAREN_EXPR
        parser_parse_expression(p)
        
        if parser_current_token(p).type_ == 25 {  // TOK_RPAREN
            parser_advance(p)
        }
    }
    
    return primary
}
