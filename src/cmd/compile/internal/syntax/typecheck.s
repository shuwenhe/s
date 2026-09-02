package compile.internal.syntax

enum type_kind {
    type_void = 0,
    type_int = 1,
    type_float = 2,
    type_string = 3,
    type_bool = 4,
    type_array = 5,
    type_slice = 6,
    type_map = 7,
    type_struct = 8,
    type_interface = 9,
    type_pointer = 10,
    type_function = 11,
    type_chan = 12,
    type_unknown = 99,
}

struct type_info {
    int kind
    string* name
    int size
    int align
    type_info* elem_type
    type_info* key_type
    type_info* val_type
    symbol_entry* fields
    int field_count
    int is_pointer
}

struct symbol_entry {
    string* name
    type_info* type_
    int kind
    int line
    int col
    int value
    symbol_entry* next
}

struct scope {
    symbol_entry* symbols
    scope* parent
    int level
}

struct typecheck_context {
    scope* current_scope
    scope* root_scope
    string* errors
    int error_count
    int max_errors
    type_info* function_return
}

func typecheck_new() typecheck_context* {
    ctx := alloc(typecheck_context)
    root_scope := alloc(scope)
    root_scope.level = 0
    root_scope.parent = nil
    typecheck_add_builtin_types(root_scope)
    ctx.root_scope = root_scope
    ctx.current_scope = root_scope
    ctx.error_count = 0
    ctx.max_errors = 100
    return ctx
}

func typecheck_add_builtin_types(scope* scope) {
    int_type := alloc(type_info)
    int_type.kind = type_int
    int_type.name = "int"
    int_type.size = 8
    int_type.align = 8
    typecheck_add_symbol(scope, "int", int_type, 0, 0, 0)
    float_type := alloc(type_info)
    float_type.kind = type_float
    float_type.name = "float64"
    float_type.size = 8
    float_type.align = 8
    typecheck_add_symbol(scope, "float64", float_type, 0, 0, 0)
    string_type := alloc(type_info)
    string_type.kind = type_string
    string_type.name = "string"
    string_type.size = 16
    string_type.align = 8
    typecheck_add_symbol(scope, "string", string_type, 0, 0, 0)
    bool_type := alloc(type_info)
    bool_type.kind = type_bool
    bool_type.name = "bool"
    bool_type.size = 1
    bool_type.align = 1
    typecheck_add_symbol(scope, "bool", bool_type, 0, 0, 0)
}

func typecheck_add_symbol(scope* scope, string name*, type_* type_info, int kind, int line, int col) {
    entry := alloc(symbol_entry)
    entry.name = name
    entry.type_ = type_
    entry.kind = kind
    entry.line = line
    entry.col = col
    entry.next = scope.symbols
    scope.symbols = entry
}

func typecheck_lookup_symbol(ctx* typecheck_context, string name*) symbol_entry* {
    scope := ctx.current_scope
    for {
        if scope == nil {
            break
        }
        entry := scope.symbols
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

func typecheck_enter_scope(ctx* typecheck_context) {
    new_scope := alloc(scope)
    new_scope.level = ctx.current_scope.level + 1
    new_scope.parent = ctx.current_scope
    ctx.current_scope = new_scope
}

func typecheck_exit_scope(ctx* typecheck_context) {
    if ctx.current_scope.parent != nil {
        ctx.current_scope = ctx.current_scope.parent
    }
}

func typecheck_expr(ctx* typecheck_context, ast_node expr*) type_info* {
    if expr == nil {
        return typecheck_get_builtin_type(ctx, "void")
    }
    if expr.type_ == ast_ident_expr {
        entry := typecheck_lookup_symbol(ctx, expr.value)
        if entry != nil {
            return entry.type_
        }
        return typecheck_get_builtin_type(ctx, "unknown")
    } else if expr.type_ == ast_literal_expr {
        return typecheck_get_literal_type(ctx, expr)
    } else if expr.type_ == ast_binary_expr {
        left_type := typecheck_expr(ctx, expr.left)
        right_type := typecheck_expr(ctx, expr.right)
        if typecheck_is_numeric(left_type) && typecheck_is_numeric(right_type) {
            return left_type
        }
        return typecheck_get_builtin_type(ctx, "unknown")
    } else if expr.type_ == ast_unary_expr {
        operand_type := typecheck_expr(ctx, expr.child)
        return operand_type
    } else if expr.type_ == ast_call_expr {
        entry := typecheck_lookup_symbol(ctx, "")
        if entry != nil && entry.type_.kind == type_function {
            return entry.type_.val_type
        }
        return typecheck_get_builtin_type(ctx, "unknown")
    } else if expr.type_ == ast_index_expr {
        array_type := typecheck_expr(ctx, nil)
        if array_type.kind == type_array {
            return array_type.elem_type
        }
        return typecheck_get_builtin_type(ctx, "unknown")
    } else if expr.type_ == ast_member_expr {
        struct_type := typecheck_expr(ctx, nil)
        if struct_type.kind == type_struct {
            i := 0
            for {
                if i >= struct_type.field_count {
                    break
                }
                i = i + 1
            }
        }
        return typecheck_get_builtin_type(ctx, "unknown")
    } else if expr.type_ == ast_paren_expr {
        return typecheck_expr(ctx, expr.child)
    }
    return typecheck_get_builtin_type(ctx, "unknown")
}

func typecheck_get_literal_type(ctx* typecheck_context, ast_node expr*) type_info* {
    return typecheck_get_builtin_type(ctx, "int")
}

func typecheck_is_numeric(type_* type_info) int {
    if type_.kind == type_int || type_.kind == type_float {
        return 1
    }
    return 0
}

func typecheck_get_builtin_type(ctx* typecheck_context, string name*) type_info* {
    entry := typecheck_lookup_symbol(ctx, name)
    if entry != nil {
        return entry.type_
    }
    unknown := alloc(type_info)
    unknown.kind = type_unknown
    unknown.name = "unknown"
    return unknown
}

func typecheck_resolve_type(ctx* typecheck_context, ast_node node*) type_info* {
    if node == nil { return typecheck_get_builtin_type(ctx, "unknown") }
    if node.type_ == ast_pointer_type {
        elem := typecheck_resolve_type(ctx, node.child)
        pointer := alloc(type_info)
        pointer.kind = type_pointer
        pointer.name = "*"
        pointer.elem_type = elem
        pointer.size = 8
        pointer.align = 8
        pointer.is_pointer = 1
        return pointer
    }
    if node.type_ == ast_array_type {
        elem := typecheck_resolve_type(ctx, node.child)
        array := alloc(type_info)
        array.kind = type_array
        array.name = "[]"
        array.elem_type = elem
        array.size = 24
        array.align = 8
        return array
    }
    if node.value != nil && node.value != "" {
        return typecheck_get_builtin_type(ctx, node.value)
    }
    return typecheck_get_builtin_type(ctx, "unknown")
}

func typecheck_is_compatible(type1* type_info, type2* type_info) int {
    if type1.kind == type2.kind {
        return 1
    }
    if (type1.kind == type_int && type2.kind == type_float) { return 1 }
    if (type1.kind == type_float && type2.kind == type_int) {
        return 1
    }
    return 0
}

func typecheck_var_decl(ctx* typecheck_context, ast_node var_decl*) int {
    if var_decl.value == nil || var_decl.value == "" {
        typecheck_error(ctx, "variable declaration requires a name", var_decl.line, var_decl.col)
        return 0
    }
    if typecheck_lookup_symbol(ctx, var_decl.value) != nil {
        typecheck_error(ctx, "duplicate variable declaration", var_decl.line, var_decl.col)
        return 0
    }
    resolved_type := typecheck_resolve_type(ctx, var_decl.child)
    if resolved_type.kind == type_unknown {
        typecheck_error(ctx, "unknown variable type", var_decl.line, var_decl.col)
        return 0
    }
    typecheck_add_symbol(ctx.current_scope, var_decl.value, resolved_type, 2, var_decl.line, var_decl.col)
    return 1
}

func typecheck_func_decl(ctx* typecheck_context, ast_node func_decl*) int {
    if func_decl.value == nil || func_decl.value == "" {
        typecheck_error(ctx, "function declaration requires a name", func_decl.line, func_decl.col)
        return 0
    }
    if typecheck_lookup_symbol(ctx, func_decl.value) != nil {
        typecheck_error(ctx, "duplicate function declaration", func_decl.line, func_decl.col)
        return 0
    }
    return_type := typecheck_resolve_type(ctx, func_decl.child)
    fn_type := alloc(type_info)
    fn_type.kind = type_function
    fn_type.name = func_decl.value
    fn_type.val_type = return_type
    typecheck_add_symbol(ctx.current_scope, func_decl.value, fn_type, 3, func_decl.line, func_decl.col)
    previous_return := ctx.function_return
    ctx.function_return = return_type
    typecheck_enter_scope(ctx)
    if func_decl.next != nil { typecheck_block_stmt(ctx, func_decl.next) }
    typecheck_exit_scope(ctx)
    ctx.function_return = previous_return
    return 1
}

func typecheck_struct_decl(ctx* typecheck_context, ast_node struct_decl*) int {
    struct_type := alloc(type_info)
    struct_type.kind = type_struct
    struct_type.name = struct_decl.value
    if struct_type.name == nil || struct_type.name == "" {
        typecheck_error(ctx, "struct declaration requires a name", struct_decl.line, struct_decl.col)
        return 0
    }
    if typecheck_lookup_symbol(ctx, struct_type.name) != nil {
        typecheck_error(ctx, "duplicate struct declaration", struct_decl.line, struct_decl.col)
        return 0
    }
    typecheck_add_symbol(ctx.current_scope, struct_type.name, struct_type, 1, struct_decl.line, struct_decl.col)
    return 1
}

func typecheck_block_stmt(ctx* typecheck_context, ast_node block*) int {
    typecheck_enter_scope(ctx)
    typecheck_exit_scope(ctx)
    return 1
}

func typecheck_return_stmt(ctx* typecheck_context, ast_node ret*) int {
    if ctx.function_return == nil {
        typecheck_error(ctx, "return outside function", ret.line, ret.col)
        return 0
    }
    actual := typecheck_expr(ctx, ret.child)
    if !typecheck_is_compatible(ctx.function_return, actual) {
        typecheck_error(ctx, "return type mismatch", ret.line, ret.col)
        return 0
    }
    return 1
}

func typecheck_if_stmt(ctx* typecheck_context, ast_node if_stmt*) int {
    cond_type := typecheck_expr(ctx, nil)
    if cond_type.kind != type_bool {
        return 0
    }
    typecheck_block_stmt(ctx, nil)
    return 1
}

func typecheck_for_stmt(ctx* typecheck_context, ast_node for_stmt*) int {
    typecheck_enter_scope(ctx)
    typecheck_exit_scope(ctx)
    return 1
}

func typecheck_statement(ctx* typecheck_context, ast_node stmt*) int {
    if stmt == nil {
        return 1
    }
    if stmt.type_ == ast_var_decl {
        return typecheck_var_decl(ctx, stmt)
    } else if stmt.type_ == ast_return_stmt {
        return typecheck_return_stmt(ctx, stmt)
    } else if stmt.type_ == ast_if_stmt {
        return typecheck_if_stmt(ctx, stmt)
    } else if stmt.type_ == ast_for_stmt {
        return typecheck_for_stmt(ctx, stmt)
    } else if stmt.type_ == ast_block_stmt {
        return typecheck_block_stmt(ctx, stmt)
    } else if stmt.type_ == ast_expr_stmt {
        typecheck_expr(ctx, nil)
        return 1
    }
    return 1
}

func typecheck_program(ctx* typecheck_context, ast_node program*) int {
    if program == nil {
        return 0
    }
    decl := program.next
    for {
        if decl == nil { break }
        if decl.type_ == ast_struct_decl { typecheck_struct_decl(ctx, decl) }
        else if decl.type_ == ast_var_decl { typecheck_var_decl(ctx, decl) }
        else if decl.type_ == ast_func_decl { typecheck_func_decl(ctx, decl) }
        decl = decl.next
    }
    return 1 - ctx.error_count
}

func typecheck_error(ctx* typecheck_context, string message*, int line, int col) {
    if ctx.error_count >= ctx.max_errors {
        return
    }
    ctx.error_count = ctx.error_count + 1
}

func typecheck_get_error_count(ctx* typecheck_context) int {
    return ctx.error_count
}
