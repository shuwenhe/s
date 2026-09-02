package compile.internal.frontend

const ast_program = 1
const ast_package = 2
const ast_import = 3
const ast_func_decl = 4
const ast_struct_decl = 5
const ast_enum_decl = 6
const ast_var_decl = 7
const ast_const_decl = 8

const ast_expr_stmt = 20
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
const ast_array_lit = 45
const ast_struct_lit = 46
const ast_ident = 47
const ast_int_lit = 48
const ast_float_lit = 49
const ast_string_lit = 50
const ast_bool_lit = 51
const ast_paren_expr = 52
const ast_cast_expr = 53

const ast_type_ident = 60
const ast_type_array = 61
const ast_type_vec = 62
const ast_type_option = 63
const ast_type_result = 64
const ast_type_func = 65
const ast_type_ptr = 66
const ast_type_mut_ptr = 67
const ast_type_struct = 68
const ast_type_enum = 69
const ast_type_generic = 70

struct ast_node {
    int node_type
    int line
    int column

    string string_data
    int int_data

    vec[ast_node] children

    string name
    string type_name
}

func ast_new(int node_type, int line, int column) ast_node* {
    node := ast_node {
        node_type: node_type,
        line: line,
        column: column,
        string_data: "",
        int_data: 0,
        children: vec[ast_node](),
        name: "",
        type_name: "",
    }
    &node
}

func ast_add_child(ast_node node*, ast_node child*) {
    node.children.push(child)
}

func ast_set_name(ast_node node*, string name) {
    node.name = name
}

func ast_set_type_name(ast_node node*, string type_name) {
    node.type_name = type_name
}

func ast_set_string_data(ast_node node*, string data) {
    node.string_data = data
}

func ast_set_int_data(ast_node node*, int data) {
    node.int_data = data
}

func ast_node_type_name(int ast_type) string {
    switch ast_type {
    case ast_program : "program"
    case ast_package : "package"
    case ast_import : "import"
    case ast_func_decl : "func_decl"
    case ast_struct_decl : "struct_decl"
    case ast_enum_decl : "enum_decl"
    case ast_var_decl : "var_decl"
    case ast_const_decl : "const_decl"
    case ast_expr_stmt : "expr_stmt"
    case ast_if_stmt : "if_stmt"
    case ast_for_stmt : "for_stmt"
    case ast_while_stmt : "while_stmt"
    case ast_return_stmt : "return_stmt"
    case ast_break_stmt : "break_stmt"
    case ast_continue_stmt : "continue_stmt"
    case ast_switch_stmt : "switch_stmt"
    case ast_block_stmt : "block_stmt"
    case ast_case_clause : "case_clause"
    case ast_binary_op : "binary_op"
    case ast_unary_op : "unary_op"
    case ast_call_expr : "call_expr"
    case ast_index_expr : "index_expr"
    case ast_member_expr : "member_expr"
    case ast_array_lit : "array_lit"
    case ast_struct_lit : "struct_lit"
    case ast_ident : "ident"
    case ast_int_lit : "int_lit"
    case ast_float_lit : "float_lit"
    case ast_string_lit : "string_lit"
    case ast_bool_lit : "bool_lit"
    case ast_paren_expr : "paren_expr"
    case ast_cast_expr : "cast_expr"
    case ast_type_ident : "type_ident"
    case ast_type_array : "type_array"
    case ast_type_vec : "type_vec"
    case ast_type_option : "type_option"
    case ast_type_result : "type_result"
    case ast_type_func : "type_func"
    case ast_type_ptr : "type_ptr"
    case ast_type_mut_ptr : "type_mut_ptr"
    case ast_type_struct : "type_struct"
    case ast_type_enum : "type_enum"
    case ast_type_generic : "type_generic"
    default : "unknown"
    }
}

func ast_dump(ast_node node*, int indent) {
    i := 0
    for i < indent {
        eprintln("  ")
        i = i + 1
    }
    eprintln(ast_node_type_name(node.node_type))
    if node.name != "" {
        eprintln(" name=")
        eprintln(node.name)
    }
    if node.type_name != "" {
        eprintln(" type=")
        eprintln(node.type_name)
    }
    eprintln("\n")

    i = 0
    for i < node.children.len() {
        ast_dump(node.children[i], indent + 1)
        i = i + 1
    }
}
