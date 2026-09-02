package compile.internal.frontend

const AST_PROGRAM = 1
const AST_PACKAGE = 2
const AST_IMPORT = 3
const AST_FUNC_DECL = 4
const AST_STRUCT_DECL = 5
const AST_ENUM_DECL = 6
const AST_VAR_DECL = 7
const AST_CONST_DECL = 8

const AST_EXPR_STMT = 20
const AST_IF_STMT = 21
const AST_FOR_STMT = 22
const AST_WHILE_STMT = 23
const AST_RETURN_STMT = 24
const AST_BREAK_STMT = 25
const AST_CONTINUE_STMT = 26
const AST_SWITCH_STMT = 27
const AST_BLOCK_STMT = 28
const AST_CASE_CLAUSE = 29

const AST_BINARY_OP = 40
const AST_UNARY_OP = 41
const AST_CALL_EXPR = 42
const AST_INDEX_EXPR = 43
const AST_MEMBER_EXPR = 44
const AST_ARRAY_LIT = 45
const AST_STRUCT_LIT = 46
const AST_IDENT = 47
const AST_INT_LIT = 48
const AST_FLOAT_LIT = 49
const AST_STRING_LIT = 50
const AST_BOOL_LIT = 51
const AST_PAREN_EXPR = 52
const AST_CAST_EXPR = 53

const AST_TYPE_IDENT = 60
const AST_TYPE_ARRAY = 61
const AST_TYPE_VEC = 62
const AST_TYPE_OPTION = 63
const AST_TYPE_RESULT = 64
const AST_TYPE_FUNC = 65
const AST_TYPE_PTR = 66
const AST_TYPE_MUT_PTR = 67
const AST_TYPE_STRUCT = 68
const AST_TYPE_ENUM = 69
const AST_TYPE_GENERIC = 70

struct ast_node {
    node_type: int
    line: int
    column: int

    string_data: string
    int_data: int

    children* ast_node[]

    name: string
    type_name: string
}

func ast_new(int node_type, int line, int column) &ast_node {
    node := new ast_node {
        node_type: node_type, line line, column column,
        string_data: "", int_data 0, children new ast_node[],
        name: "",
        type_name: ""
    }
    &node
}

func ast_add_child(node* ast_node, child* ast_node) {
    node.children.push(child)
}

func ast_set_name(node* ast_node, string name) {
    node.name = name
}

func ast_set_type_name(node* ast_node, string type_name) {
    node.type_name = type_name
}

func ast_set_string_data(node* ast_node, string data) {
    node.string_data = data
}

func ast_set_int_data(node* ast_node, int data) {
    node.int_data = data
}

func ast_node_type_name(int ast_type) string {
    switch ast_type {
    case AST_PROGRAM : "PROGRAM"
    case AST_PACKAGE : "PACKAGE"
    case AST_IMPORT : "IMPORT"
    case AST_FUNC_DECL : "FUNC_DECL"
    case AST_STRUCT_DECL : "STRUCT_DECL"
    case AST_ENUM_DECL : "ENUM_DECL"
    case AST_VAR_DECL : "VAR_DECL"
    case AST_CONST_DECL : "CONST_DECL"
    case AST_EXPR_STMT : "EXPR_STMT"
    case AST_IF_STMT : "IF_STMT"
    case AST_FOR_STMT : "FOR_STMT"
    case AST_WHILE_STMT : "WHILE_STMT"
    case AST_RETURN_STMT : "RETURN_STMT"
    case AST_BREAK_STMT : "BREAK_STMT"
    case AST_CONTINUE_STMT : "CONTINUE_STMT"
    case AST_SWITCH_STMT : "SWITCH_STMT"
    case AST_BLOCK_STMT : "BLOCK_STMT"
    case AST_CASE_CLAUSE : "CASE_CLAUSE"
    case AST_BINARY_OP : "BINARY_OP"
    case AST_UNARY_OP : "UNARY_OP"
    case AST_CALL_EXPR : "CALL_EXPR"
    case AST_INDEX_EXPR : "INDEX_EXPR"
    case AST_MEMBER_EXPR : "MEMBER_EXPR"
    case AST_ARRAY_LIT : "ARRAY_LIT"
    case AST_STRUCT_LIT : "STRUCT_LIT"
    case AST_IDENT : "IDENT"
    case AST_INT_LIT : "INT_LIT"
    case AST_FLOAT_LIT : "FLOAT_LIT"
    case AST_STRING_LIT : "STRING_LIT"
    case AST_BOOL_LIT : "BOOL_LIT"
    case AST_PAREN_EXPR : "PAREN_EXPR"
    case AST_CAST_EXPR : "CAST_EXPR"
    case AST_TYPE_IDENT : "TYPE_IDENT"
    case AST_TYPE_ARRAY : "TYPE_ARRAY"
    case AST_TYPE_VEC : "TYPE_VEC"
    case AST_TYPE_OPTION : "TYPE_OPTION"
    case AST_TYPE_RESULT : "TYPE_RESULT"
    case AST_TYPE_FUNC : "TYPE_FUNC"
    case AST_TYPE_PTR : "TYPE_PTR"
    case AST_TYPE_MUT_PTR : "TYPE_MUT_PTR"
    case AST_TYPE_STRUCT : "TYPE_STRUCT"
    case AST_TYPE_ENUM : "TYPE_ENUM"
    case AST_TYPE_GENERIC : "TYPE_GENERIC"
    default : "UNKNOWN"
    }
}

func ast_dump(node* ast_node, int indent) {
    for i := 0; i < indent; i = i + 1 {
        eprintln("  ")
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

    for i := 0; i < node.children.len(); i = i + 1 {
        ast_dump(node.children[i], indent + 1)
    }
}
