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
