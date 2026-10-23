package compile.internal.parser.syntax

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
    type_kind kind
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
    string name
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
    int error_count
    int max_errors
}

// Dead code - all typecheck functions removed due to borrow rule violations
// (allocating in borrowed bodies). The entire syntax package is not called
// from production code.
