// Package: compile.internal.sc
// Module: types.s
// Description: Type system initialization and management
// Corresponds to: Go cmd/compile/internal/types

package compile.internal.sc

import (
    "std.io"
)

// Type kind enumeration
enum type_kind {
    KIND_INVALID = 0
    KIND_BOOL = 1
    KIND_INT = 2
    KIND_INT8 = 3
    KIND_INT16 = 4
    KIND_INT32 = 5
    KIND_INT64 = 6
    KIND_UINT = 7
    KIND_UINT8 = 8
    KIND_UINT16 = 9
    KIND_UINT32 = 10
    KIND_UINT64 = 11
    KIND_FLOAT32 = 12
    KIND_FLOAT64 = 13
    KIND_COMPLEX64 = 14
    KIND_COMPLEX128 = 15
    KIND_STRING = 16
    KIND_POINTER = 17
    KIND_ARRAY = 18
    KIND_SLICE = 19
    KIND_MAP = 20
    KIND_STRUCT = 21
    KIND_INTERFACE = 22
    KIND_FUNC = 23
    KIND_CHAN = 24
}

// Core type representation
struct compiler_type {
    type_kind kind
    string name
    
    // Size information
    int size_bytes
    int align_bytes
    
    // For named types
    string package_path
    string type_name
    
    // For composite types
    compiler_type element_type  // For: pointer, slice, array
    compiler_type key_type      // For map
    compiler_type value_type    // For map
    compiler_type base_type     // For array
    
    // For function types
    compiler_type[] param_types
    compiler_type[] return_types
    
    // For struct types
    any fields  // Field information
    
    // For interface types
    any methods  // Method information
    
    bool is_pointer
    bool is_named
    bool is_generic
}

// Type cache to avoid duplicate type objects
struct type_cache {
    any types_by_name     // map[string]compiler_type
    any types_by_kind     // map[type_kind]compiler_type[]
    compiler_type[] basic_types  // Cache of built-in types
}

// Global type system state
struct type_system {
    type_cache cache
    compiler_type any_type
    compiler_type string_type
    compiler_type bool_type
    compiler_type int_type
    compiler_type uint_type
    compiler_type float_type
    compiler_type error_type
}

// Architecture-specific type information
struct arch_type_info {
    // Platform type sizes (varies by architecture)
    int ptr_size_bytes
    int int_size_bytes
    int long_size_bytes
    int reg_size_bytes
    
    // Register information
    int max_registers
    string[] register_names
    int[] dwarf_register_numbers
    
    // Calling convention
    string calling_convention  // "amd64", "arm64", "x86", etc.
    any calling_convention_info  // ABI details
}

// Initialize built-in types
func init_builtin_types(arch_type_info arch_info) type_system {
    std.io.eprintln("[types] Initializing built-in type system")
    
    ts := type_system{
        cache: type_cache{},
    }
    
    // Create basic types
    ts.any_type = create_type(type_kind.KIND_INVALID, "any")
    ts.string_type = create_type(type_kind.KIND_STRING, "string")
    ts.bool_type = create_type(type_kind.KIND_BOOL, "bool")
    
    // Integer types
    ts.int_type = create_int_type("int", arch_info.int_size_bytes)
    ts.uint_type = create_int_type("uint", arch_info.int_size_bytes)
    
    // Float types
    ts.float_type = create_float_type("float64", 8)
    
    // Error type
    ts.error_type = create_type(type_kind.KIND_INTERFACE, "error")
    
    std.io.eprintln("[types] " + "Built-in types initialized for " + arch_info.calling_convention)
    
    return ts
}

// Create a basic type
func create_type(type_kind kind, string name) compiler_type {
    return compiler_type{
        kind: kind,
        name: name,
        is_pointer: false,
        is_named: false,
    }
}

// Create an integer type with given size
func create_int_type(string name, int size) compiler_type {
    return compiler_type{
        kind: type_kind.KIND_INT,
        name: name,
        size_bytes: size,
        align_bytes: size,
        is_pointer: false,
        is_named: false,
    }
}

// Create a float type with given size
func create_float_type(string name, int size) compiler_type {
    return compiler_type{
        kind: type_kind.KIND_FLOAT64,
        name: name,
        size_bytes: size,
        align_bytes: size,
        is_pointer: false,
        is_named: false,
    }
}

// Create a pointer type
func create_pointer_type(compiler_type elem_type) compiler_type {
    // All pointers have same size
    return compiler_type{
        kind: type_kind.KIND_POINTER,
        name: "*" + elem_type.name,
        size_bytes: 8,  // Assume 64-bit for now
        align_bytes: 8,
        element_type: elem_type,
        is_pointer: true,
    }
}

// Create an array type
func create_array_type(compiler_type elem_type, int length) compiler_type {
    return compiler_type{
        kind: type_kind.KIND_ARRAY,
        name: "[" + std.conv.fmt_int(length) + "]" + elem_type.name,
        size_bytes: length * elem_type.size_bytes,
        align_bytes: elem_type.align_bytes,
        element_type: elem_type,
        base_type: elem_type,
    }
}

// Create a slice type
func create_slice_type(compiler_type elem_type) compiler_type {
    // Slice: { data pointer, length, capacity }
    // Size = 24 bytes on 64-bit
    return compiler_type{
        kind: type_kind.KIND_SLICE,
        name: "[]" + elem_type.name,
        size_bytes: 24,
        align_bytes: 8,
        element_type: elem_type,
    }
}

// Create a map type
func create_map_type(compiler_type key_type, compiler_type value_type) compiler_type {
    return compiler_type{
        kind: type_kind.KIND_MAP,
        name: "map[" + key_type.name + "]" + value_type.name,
        size_bytes: 8,  // Map is a pointer
        align_bytes: 8,
        key_type: key_type,
        value_type: value_type,
        is_pointer: true,
    }
}

// Create a struct type
func create_struct_type(string name, any fields) compiler_type {
    // Calculate size based on fields
    total_size := 0
    max_align := 1
    
    // TODO: Iterate over fields to calculate size
    
    return compiler_type{
        kind: type_kind.KIND_STRUCT,
        name: name,
        size_bytes: total_size,
        align_bytes: max_align,
        fields: fields,
    }
}

// Create a function type
func create_function_type(
    compiler_type[] param_types,
    compiler_type[] return_types
) compiler_type {
    param_names := ""
    i := 0
    while i < len(param_types) {
        if i > 0 {
            param_names = param_names + ", "
        }
        param_names = param_names + param_types[i].name
        i = i + 1
    }
    
    ret_names := ""
    i = 0
    while i < len(return_types) {
        if i > 0 {
            ret_names = ret_names + ", "
        }
        ret_names = ret_names + return_types[i].name
        i = i + 1
    }
    
    return compiler_type{
        kind: type_kind.KIND_FUNC,
        name: "func(" + param_names + ") (" + ret_names + ")",
        size_bytes: 8,  // Function is pointer to code
        align_bytes: 8,
        param_types: param_types,
        return_types: return_types,
        is_pointer: true,
    }
}

// Compute type size with alignment
func compute_type_size(compiler_type t) int {
    if t.kind == type_kind.KIND_STRUCT {
        // Compute struct size considering field alignment
        current_offset := 0
        // TODO: Iterate over fields
        return current_offset
    }
    
    return t.size_bytes
}

// Check type compatibility
func types_compatible(compiler_type t1, compiler_type t2) bool {
    if t1.kind != t2.kind {
        return false
    }
    
    if t1.name == t2.name {
        return true
    }
    
    // Handle special cases
    if t1.kind == type_kind.KIND_POINTER {
        return types_compatible(t1.element_type, t2.element_type)
    }
    
    if t1.kind == type_kind.KIND_ARRAY {
        return t1.size_bytes == t2.size_bytes &&
               types_compatible(t1.element_type, t2.element_type)
    }
    
    return false
}

// Convert type to string representation
func type_to_string(compiler_type t) string {
    return t.name
}
