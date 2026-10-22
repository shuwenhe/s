package compile.internal.ir

import (
    "compile.internal.parser"
)

struct ir_builder_context {
    ir_module module
    ir_function current_function
    ir_basicblock current_block

    ir_symbol_table symbol_table
    type_system type_system

    int block_counter
    int value_counter

    string[] errors
}

struct ir_symbol_table {
    ir_ir_symbol[] symbols
    ir_scope[] scopes
}

struct ir_ir_symbol {
    string name
    ir_value ir_value
    int block_id
}

struct ir_scope {
    int symbol_count
    int depth
}

struct type_system {
    string_ir_type_map type_cache
}

