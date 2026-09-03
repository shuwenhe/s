package types_complete

const type_invalid = 0
const type_int = 1
const type_float = 2
const type_string = 3
const type_bool = 4
const type_char = 5
const type_void = 6
const type_ptr = 7
const type_array = 8
const type_slice = 9
const type_map = 10
const type_struct = 11
const type_enum = 12
const type_interface = 13
const type_func = 14
const type_generic = 15
const type_named = 16
const type_union = 17
const type_error = 18

struct type_constraint {
    name string
    bounds string[]
    methods string[]
}

struct type_param {
    name string
    constraint type_constraint
    index int
}

struct generic_type {
    name string
    params type_param[]
    instantiations type_info[]
}

struct method_info {
    name string
    receiver string
    params string[]
    returns string[]
    is_pointer int
}

struct type_info {
    kind int
    name string
    size int
    align int
    fields string[]
    methods method_info[]
    constraints type_constraint[]
    generic_params type_param[]
    underlying string
    elem_type string
    key_type string
    value_type string
    params string[]
    returns string[]
}

struct type_table {
    types type_info[]
    named_types type_info[]
    generics generic_type[]
    method_sets method_info[][]
}

var global_type_table type_table

func type_table_new() type_table {
    table := type_table { types: type_info[](), named_types: type_info[](), generics: generic_type[](), method_sets: method_info[][]() }
    table
}

func type_register_builtin(type_table* table) {
    int_type := type_info { kind: type_int, name: "int", size: 8, align: 8 }
    table.types = append(table.types, int_type)
    
    float_type := type_info { kind: type_float, name: "float", size: 8, align: 8 }
    table.types = append(table.types, float_type)
    
    string_type := type_info { kind: type_string, name: "string", size: 24, align: 8 }
    table.types = append(table.types, string_type)
    
    bool_type := type_info { kind: type_bool, name: "bool", size: 1, align: 1 }
    table.types = append(table.types, bool_type)
}

func type_lookup(type_table* table, string name) type_info {
    for i := 0; i < table.types.len(); i = i + 1 {
        if table.types[i].name == name {
            return table.types[i]
        }
    }
    
    type_info { kind: type_invalid, name: "invalid" }
}

func type_create_pointer(type_table* table, string elem_type) type_info {
    ptr_type := type_info { 
        kind: type_ptr, 
        name: elem_type + "*", 
        size: 8, 
        align: 8,
        elem_type: elem_type 
    }
    table.types = append(table.types, ptr_type)
    ptr_type
}

func type_create_array(type_table* table, string elem_type, int size) type_info {
    elem := type_lookup(table, elem_type)
    array_type := type_info { 
        kind: type_array, 
        name: elem_type + "[]", 
        size: elem.size * size, 
        align: elem.align,
        elem_type: elem_type 
    }
    table.types = append(table.types, array_type)
    array_type
}

func type_create_slice(type_table* table, string elem_type) type_info {
    slice_type := type_info { 
        kind: type_slice, 
        name: "[]" + elem_type, 
        size: 24, 
        align: 8,
        elem_type: elem_type 
    }
    table.types = append(table.types, slice_type)
    slice_type
}

func type_create_func(type_table* table, string[] params, string[] returns) type_info {
    func_name := "func("
    for i := 0; i < params.len(); i = i + 1 {
        if i > 0 {
            func_name = func_name + ", "
        }
        func_name = func_name + params[i]
    }
    func_name = func_name + ") ("
    for i := 0; i < returns.len(); i = i + 1 {
        if i > 0 {
            func_name = func_name + ", "
        }
        func_name = func_name + returns[i]
    }
    func_name = func_name + ")"
    
    func_type := type_info { 
        kind: type_func, 
        name: func_name, 
        size: 16, 
        align: 8,
        params: params,
        returns: returns
    }
    table.types = append(table.types, func_type)
    func_type
}

func type_create_struct(type_table* table, string name, string[] fields) type_info {
    struct_type := type_info { 
        kind: type_struct, 
        name: name, 
        size: 0, 
        align: 8,
        fields: fields
    }
    table.types = append(table.types, struct_type)
    struct_type
}

func type_create_interface(type_table* table, string name, string[] methods) type_info {
    iface_type := type_info { 
        kind: type_interface, 
        name: name, 
        size: 16, 
        align: 8,
        methods: method_info[]()
    }
    table.types = append(table.types, iface_type)
    iface_type
}

func type_add_method(type_table* table, string type_name, method_info method) {
    for i := 0; i < table.types.len(); i = i + 1 {
        if table.types[i].name == type_name {
            table.types[i].methods = append(table.types[i].methods, method)
        }
    }
}

func type_create_generic(type_table* table, string name, type_param[] params) generic_type {
    gen_type := generic_type { 
        name: name, 
        params: params, 
        instantiations: type_info[]() 
    }
    table.generics = append(table.generics, gen_type)
    gen_type
}

func type_instantiate_generic(type_table* table, string generic_name, string[] type_args) type_info {
    inst_name := generic_name + "["
    for i := 0; i < type_args.len(); i = i + 1 {
        if i > 0 {
            inst_name = inst_name + ", "
        }
        inst_name = inst_name + type_args[i]
    }
    inst_name = inst_name + "]"
    
    type_info { kind: type_generic, name: inst_name }
}

func type_is_assignable(type_table* table, string from_type, string to_type) int {
    if from_type == to_type {
        return 1
    }
    
    from := type_lookup(table, from_type)
    to := type_lookup(table, to_type)
    
    if from.kind == type_invalid || to.kind == type_invalid {
        return 0
    }
    
    if from.kind == type_ptr && to.kind == type_ptr {
        return type_is_assignable(table, from.elem_type, to.elem_type)
    }
    
    return 0
}

func type_implements_interface(type_table* table, string type_name, string interface_name) int {
    type_type := type_lookup(table, type_name)
    iface := type_lookup(table, interface_name)
    
    if iface.kind != type_interface {
        return 0
    }
    
    for i := 0; i < iface.methods.len(); i = i + 1 {
        iface_method := iface.methods[i]
        
        found := 0
        for j := 0; j < type_type.methods.len(); j = j + 1 {
            type_method := type_type.methods[j]
            if type_method.name == iface_method.name {
                found = 1
                break
            }
        }
        
        if found == 0 {
            return 0
        }
    }
    
    return 1
}

func type_info_to_string(type_info t) string {
    t.name
}
