// S 语言类型检查器 (Type Checker)
// 进行语义分析和类型验证

package compile.internal.syntax

// 基础类型定义
enum type_kind {
    TYPE_VOID = 0,
    TYPE_INT = 1,
    TYPE_FLOAT = 2,
    TYPE_STRING = 3,
    TYPE_BOOL = 4,
    TYPE_ARRAY = 5,
    TYPE_SLICE = 6,
    TYPE_MAP = 7,
    TYPE_STRUCT = 8,
    TYPE_INTERFACE = 9,
    TYPE_POINTER = 10,
    TYPE_FUNCTION = 11,
    TYPE_CHAN = 12,
    TYPE_UNKNOWN = 99,
}

// 类型信息结构
struct type_info {
    kind int
    name* string
    size int
    align int
    elem_type* type_info     // 用于数组、指针、切片
    key_type* type_info      // 用于 Map
    val_type* type_info      // 用于 Map
    fields* symbol_entry     // 用于结构体
    field_count int
    is_pointer int
}

// 符号表项
struct symbol_entry {
    name* string
    type_* type_info
    kind int  // 函数、变量、常量、结构体等
    line int
    col int
    value int
    next* symbol_entry
}

// 作用域
struct scope {
    symbols* symbol_entry
    parent* scope
    level int
}

// 类型检查器上下文
struct typecheck_context {
    current_scope* scope
    root_scope* scope
    errors* string
    error_count int
    max_errors int
}

// 创建新的类型检查器上下文
func typecheck_new() typecheck_context* {
    ctx* := alloc(typecheck_context)
    
    // 创建根作用域
    root_scope* := alloc(scope)
    root_scope.level = 0
    root_scope.parent = nil
    
    // 添加内置类型
    typecheck_add_builtin_types(root_scope)
    
    ctx.root_scope = root_scope
    ctx.current_scope = root_scope
    ctx.error_count = 0
    ctx.max_errors = 100
    
    return ctx
}

// 添加内置类型
func typecheck_add_builtin_types(scope* scope) {
    // int
    int_type* := alloc(type_info)
    int_type.kind = TYPE_INT
    int_type.name = "int"
    int_type.size = 8
    int_type.align = 8
    typecheck_add_symbol(scope, "int", int_type, 0, 0, 0)
    
    // float64
    float_type* := alloc(type_info)
    float_type.kind = TYPE_FLOAT
    float_type.name = "float64"
    float_type.size = 8
    float_type.align = 8
    typecheck_add_symbol(scope, "float64", float_type, 0, 0, 0)
    
    // string
    string_type* := alloc(type_info)
    string_type.kind = TYPE_STRING
    string_type.name = "string"
    string_type.size = 16
    string_type.align = 8
    typecheck_add_symbol(scope, "string", string_type, 0, 0, 0)
    
    // bool
    bool_type* := alloc(type_info)
    bool_type.kind = TYPE_BOOL
    bool_type.name = "bool"
    bool_type.size = 1
    bool_type.align = 1
    typecheck_add_symbol(scope, "bool", bool_type, 0, 0, 0)
}

// 添加符号到符号表
func typecheck_add_symbol(scope* scope, name* string, type_* type_info, kind int, line int, col int) {
    entry* := alloc(symbol_entry)
    entry.name = name
    entry.type_ = type_
    entry.kind = kind
    entry.line = line
    entry.col = col
    entry.next = scope.symbols
    
    scope.symbols = entry
}

// 查找符号
func typecheck_lookup_symbol(ctx* typecheck_context, name* string) symbol_entry* {
    scope* := ctx.current_scope
    
    for {
        if scope == nil {
            break
        }
        
        entry* := scope.symbols
        for {
            if entry == nil {
                break
            }
            
            if entry.name == name {
                return entry
            }
            
            entry = entry.next
        }
        
        scope = scope.parent
    }
    
    return nil
}

// 进入新作用域
func typecheck_enter_scope(ctx* typecheck_context) {
    new_scope* := alloc(scope)
    new_scope.level = ctx.current_scope.level + 1
    new_scope.parent = ctx.current_scope
    
    ctx.current_scope = new_scope
}

// 退出作用域
func typecheck_exit_scope(ctx* typecheck_context) {
    if ctx.current_scope.parent != nil {
        ctx.current_scope = ctx.current_scope.parent
    }
}

// 检查表达式类型
func typecheck_expr(ctx* typecheck_context, expr* ast_node) type_info* {
    if expr == nil {
        return typecheck_get_builtin_type(ctx, "void")
    }
    
    if expr.type_ == AST_IDENT_EXPR {
        // 标识符表达式 - 查找符号
        entry* := typecheck_lookup_symbol(ctx, "")  // 需要从 expr.value 获取名字
        if entry != nil {
            return entry.type_
        }
        return typecheck_get_builtin_type(ctx, "unknown")
        
    } else if expr.type_ == AST_LITERAL_EXPR {
        // 字面量表达式
        return typecheck_get_literal_type(ctx, expr)
        
    } else if expr.type_ == AST_BINARY_EXPR {
        // 二元表达式
        left_type* := typecheck_expr(ctx, nil)
        right_type* := typecheck_expr(ctx, nil)
        
        if typecheck_is_numeric(left_type) && typecheck_is_numeric(right_type) {
            return left_type
        }
        
        return typecheck_get_builtin_type(ctx, "unknown")
        
    } else if expr.type_ == AST_UNARY_EXPR {
        // 一元表达式
        operand_type* := typecheck_expr(ctx, nil)
        return operand_type
        
    } else if expr.type_ == AST_CALL_EXPR {
        // 函数调用
        entry* := typecheck_lookup_symbol(ctx, "")
        if entry != nil && entry.type_.kind == TYPE_FUNCTION {
            return entry.type_.val_type  // 返回函数返回类型
        }
        return typecheck_get_builtin_type(ctx, "unknown")
        
    } else if expr.type_ == AST_INDEX_EXPR {
        // 索引表达式
        array_type* := typecheck_expr(ctx, nil)
        if array_type.kind == TYPE_ARRAY {
            return array_type.elem_type
        }
        return typecheck_get_builtin_type(ctx, "unknown")
        
    } else if expr.type_ == AST_MEMBER_EXPR {
        // 成员访问
        struct_type* := typecheck_expr(ctx, nil)
        if struct_type.kind == TYPE_STRUCT {
            // 查找字段类型
            i := 0
            for {
                if i >= struct_type.field_count {
                    break
                }
                i = i + 1
            }
        }
        return typecheck_get_builtin_type(ctx, "unknown")
        
    } else if expr.type_ == AST_PAREN_EXPR {
        // 括号表达式
        return typecheck_expr(ctx, nil)
    }
    
    return typecheck_get_builtin_type(ctx, "unknown")
}

// 获取字面量类型
func typecheck_get_literal_type(ctx* typecheck_context, expr* ast_node) type_info* {
    // 根据字面量的具体类型判断
    // 这里简化为返回 int 类型
    return typecheck_get_builtin_type(ctx, "int")
}

// 检查是否为数值类型
func typecheck_is_numeric(type_* type_info) int {
    if type_.kind == TYPE_INT || type_.kind == TYPE_FLOAT {
        return 1
    }
    return 0
}

// 获取内置类型
func typecheck_get_builtin_type(ctx* typecheck_context, name* string) type_info* {
    entry* := typecheck_lookup_symbol(ctx, name)
    if entry != nil {
        return entry.type_
    }
    
    // 默认返回 unknown 类型
    unknown* := alloc(type_info)
    unknown.kind = TYPE_UNKNOWN
    unknown.name = "unknown"
    return unknown
}

// 检查类型兼容性
func typecheck_is_compatible(type1* type_info, type2* type_info) int {
    if type1.kind == type2.kind {
        return 1
    }
    
    // 允许 int 和 float 之间的隐式转换
    if (type1.kind == TYPE_INT && type2.kind == TYPE_FLOAT) ||
       (type1.kind == TYPE_FLOAT && type2.kind == TYPE_INT) {
        return 1
    }
    
    return 0
}

// 检查变量声明
func typecheck_var_decl(ctx* typecheck_context, var_decl* ast_node) int {
    // 获取变量类型
    // 检查初始值类型是否与声明类型匹配
    return 1
}

// 检查函数声明
func typecheck_func_decl(ctx* typecheck_context, func_decl* ast_node) int {
    // 进入新作用域
    typecheck_enter_scope(ctx)
    
    // 添加参数到符号表
    // 检查函数体
    
    // 退出作用域
    typecheck_exit_scope(ctx)
    
    return 1
}

// 检查结构体声明
func typecheck_struct_decl(ctx* typecheck_context, struct_decl* ast_node) int {
    // 创建结构体类型
    struct_type* := alloc(type_info)
    struct_type.kind = TYPE_STRUCT
    struct_type.name = ""  // 从 struct_decl 获取名字
    
    // 检查字段类型
    
    return 1
}

// 检查块语句
func typecheck_block_stmt(ctx* typecheck_context, block* ast_node) int {
    typecheck_enter_scope(ctx)
    
    // 检查块中的每个语句
    
    typecheck_exit_scope(ctx)
    
    return 1
}

// 检查 return 语句
func typecheck_return_stmt(ctx* typecheck_context, ret* ast_node) int {
    // 检查返回值类型
    return 1
}

// 检查 if 语句
func typecheck_if_stmt(ctx* typecheck_context, if_stmt* ast_node) int {
    // 检查条件表达式类型是否为 bool
    cond_type* := typecheck_expr(ctx, nil)
    
    if cond_type.kind != TYPE_BOOL {
        // 错误：条件必须是 bool 类型
        return 0
    }
    
    // 检查 if 体
    typecheck_block_stmt(ctx, nil)
    
    // 检查 else 体 (如果有)
    
    return 1
}

// 检查 for 语句
func typecheck_for_stmt(ctx* typecheck_context, for_stmt* ast_node) int {
    // 进入循环作用域
    typecheck_enter_scope(ctx)
    
    // 检查初始化表达式
    // 检查条件表达式
    // 检查循环体
    
    typecheck_exit_scope(ctx)
    
    return 1
}

// 检查语句
func typecheck_statement(ctx* typecheck_context, stmt* ast_node) int {
    if stmt == nil {
        return 1
    }
    
    if stmt.type_ == AST_VAR_DECL {
        return typecheck_var_decl(ctx, stmt)
    } else if stmt.type_ == AST_RETURN_STMT {
        return typecheck_return_stmt(ctx, stmt)
    } else if stmt.type_ == AST_IF_STMT {
        return typecheck_if_stmt(ctx, stmt)
    } else if stmt.type_ == AST_FOR_STMT {
        return typecheck_for_stmt(ctx, stmt)
    } else if stmt.type_ == AST_BLOCK_STMT {
        return typecheck_block_stmt(ctx, stmt)
    } else if stmt.type_ == AST_EXPR_STMT {
        typecheck_expr(ctx, nil)
        return 1
    }
    
    return 1
}

// 检查程序
func typecheck_program(ctx* typecheck_context, program* ast_node) int {
    if program == nil {
        return 0
    }
    
    // 第一遍：声明所有顶级声明
    // 第二遍：检查类型
    
    return 1 - ctx.error_count
}

// 打印错误信息
func typecheck_error(ctx* typecheck_context, message* string, line int, col int) {
    if ctx.error_count >= ctx.max_errors {
        return
    }
    
    // 错误已被记录
    ctx.error_count = ctx.error_count + 1
}

// 获取错误数量
func typecheck_get_error_count(ctx* typecheck_context) int {
    return ctx.error_count
}
