package compile.internal.frontend

struct symbol {
    name: string
    symbol_kind: int
    value_type: string
    scope_depth: int
    line: int
    column: int
    is_exported: int
    is_mut: int
}

const SYMBOL_VAR = 1
const SYMBOL_FUNC = 2
const SYMBOL_STRUCT = 3
const SYMBOL_ENUM = 4
const SYMBOL_CONST = 5
const SYMBOL_PARAM = 6
const SYMBOL_FIELD = 7

struct symbol_table {
    symbols: symbol[]
    scope_stack: int[]
    current_scope: int
}

struct semantic_result {
    ast* ast_node
    symbols: symbol_table
    errors: string[]
    type_info: string[]
}

func symbol_table_new() symbol_table {
    symbol_table {
        symbols: vec[symbol](), scope_stack vec[int](), current_scope 0
    }
}

func symbol_table_push_scope(st* symbol_table) {
    st.scope_stack.push(st.current_scope)
    st.current_scope = st.current_scope + 1
}

func symbol_table_pop_scope(st* symbol_table) {
    if st.scope_stack.len() > 0 {
        st.current_scope = st.scope_stack[st.scope_stack.len() - 1]
        st.scope_stack.pop()
    }
}

func symbol_table_define(st* symbol_table, string name, int kind, string type_name) int {
    for i := 0; i < st.symbols.len(); i = i + 1 {
        if st.symbols[i].name == name && st.symbols[i].scope_depth == st.current_scope {
            return 0
        }
    }
    
    sym := symbol {
        name: name, symbol_kind kind, value_type type_name, scope_depth st.current_scope, line 0, column 0, is_exported 0, is_mut 0
    }
    st.symbols.push(sym)
    1
}

func symbol_table_lookup(st* symbol_table, string name) &symbol {
    for i := st.symbols.len() - 1; i >= 0; i = i - 1 {
        if st.symbols[i].name == name {
            return &st.symbols[i]
        }
    }
    0
}

struct type_system {
    defined_types: string[]
    type_relations: int[][]
}

func type_system_new() type_system {
    type_system {
        defined_types: vec[string](), type_relations vec[int[]]()
    }
}

func type_is_valid(string type_name) int {
    if type_name == "int" || type_name == "float" || type_name == "string" || type_name == "bool" || type_name == "char" || type_name == "void" {
        return 1
    }
    
    if type_name[0] == '&' {
        return 1
    }
    
    0
}

func types_compatible(string type1, string type2) int {
    if type1 == type2 {
        return 1
    }
    
    0
}

struct semantic_analyzer {
    symbols: symbol_table
    types: type_system
    errors: string[]
    current_function* ast_node
    in_loop: int
    in_function: int
}

func semantic_analyzer_new() semantic_analyzer {
    semantic_analyzer {
        symbols: symbol_table_new(), types type_system_new(), errors vec[string](), current_function 0, in_loop 0, in_function 0
    }
}

func semantic_analyzer_add_error(ana* semantic_analyzer, string msg) {
    ana.errors.push(msg)
}

func semantic_analyze(ast* ast_node) semantic_result {
    ana := semantic_analyzer_new()
    
    semantic_analyze_node(&mut ana, ast)
    
    semantic_result {
        ast: ast, symbols ana.symbols, errors ana.errors, type_info vec[string]()
    }
}

func semantic_analyze_node(ana* semantic_analyzer, node* ast_node) {
    if node == 0 {
        return
    }
    
    switch node.node_type {
    case AST_PROGRAM :
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_PACKAGE :
        return
    
    case AST_IMPORT :
        return
    
    case AST_FUNC_DECL :
        ana.in_function = 1
        symbol_table_define(&mut ana.symbols, node.name, SYMBOL_FUNC, "")
        symbol_table_push_scope(&mut ana.symbols)
        
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
        
        symbol_table_pop_scope(&mut ana.symbols)
        ana.in_function = 0
    
    case AST_STRUCT_DECL :
        symbol_table_define(&mut ana.symbols, node.name, SYMBOL_STRUCT, "")
        symbol_table_push_scope(&mut ana.symbols)
        
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
        
        symbol_table_pop_scope(&mut ana.symbols)
    
    case AST_ENUM_DECL :
        symbol_table_define(&mut ana.symbols, node.name, SYMBOL_ENUM, "")
    
    case AST_VAR_DECL :
        if node.type_name == "" {
            semantic_analyzer_add_error(ana, "Variable " + node.name + " has no type")
        }
        symbol_table_define(&mut ana.symbols, node.name, SYMBOL_VAR, node.type_name)
        
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_CONST_DECL :
        symbol_table_define(&mut ana.symbols, node.name, SYMBOL_CONST, node.type_name)
        
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_FOR_STMT :
        ana.in_loop = 1
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
        ana.in_loop = 0
    
    case AST_WHILE_STMT :
        ana.in_loop = 1
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
        ana.in_loop = 0
    
    case AST_BREAK_STMT :
        if !ana.in_loop {
            semantic_analyzer_add_error(ana, "break statement outside loop")
        }
    
    case AST_CONTINUE_STMT :
        if !ana.in_loop {
            semantic_analyzer_add_error(ana, "continue statement outside loop")
        }
    
    case AST_RETURN_STMT :
        if !ana.in_function {
            semantic_analyzer_add_error(ana, "return statement outside function")
        }
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_BLOCK_STMT :
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_IF_STMT :
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_SWITCH_STMT :
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_EXPR_STMT :
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_BINARY_OP :
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_UNARY_OP :
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_CALL_EXPR :
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    
    case AST_IDENT :
        if symbol_table_lookup(&ana.symbols, node.name) == 0 {
            semantic_analyzer_add_error(ana, "undefined identifier: " + node.name)
        }
    
    default :
        for i := 0; i < node.children.len(); i = i + 1 {
            semantic_analyze_node(ana, node.children[i])
        }
    }
}
