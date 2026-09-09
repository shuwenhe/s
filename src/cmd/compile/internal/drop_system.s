package compile.internal.drop_system

use compile.internal.typesys.is_copy_type

struct dtor_field {
    string name
    string type_name
    bool needs_drop
}

struct dtor_impl {
    string type_name
    bool custom
    string function_name
    dtor_field[] fields
}

struct dtor_registry {
    dtor_impl[] impls
}

struct dtor_check_result {
    bool ok
    string message
}

func dtor_registry_new() dtor_registry {
    dtor_impl[] impls
    dtor_registry { impls: impls }
}

func dtor_impl_new(string type_name, bool custom, string function_name) dtor_impl {
    dtor_field[] fields
    dtor_impl { type_name: type_name, custom: custom, function_name: function_name, fields: fields }
}

func dtor_field_new(string name, string type_name) dtor_field {
    dtor_field { name: name, type_name: type_name, needs_drop: type_needs_drop(type_name) }
}

func dtor_impl_add_field(dtor_impl impl, string name, string type_name) dtor_impl {
    impl.fields = append(impl.fields, dtor_field_new(name, type_name))
    impl
}

func dtor_registry_register(dtor_registry registry, dtor_impl impl) dtor_registry {
    registry.impls = append(registry.impls, impl)
    registry
}

func dtor_registry_find(dtor_registry registry, string type_name) int {
    i := 0
    for i < len(registry.impls) {
        if registry.impls[i].type_name == type_name { return i }
        i = i + 1
    }
    -1
}

func dtor_registry_needs_drop(dtor_registry registry, string type_name) bool {
    if type_needs_drop(type_name) { return true }
    dtor_registry_find(registry, type_name) >= 0
}

func type_needs_drop(string type_name) bool {
    if type_name == "" { return false }
    if is_copy_type(type_name) { return false }
    if starts_with(type_name, "&") { return false }
    if ends_with(type_name, "*") { return false }
    if type_name == "ref" || type_name == "mutref" { return false }
    type_name == "box" || type_name == "pair" || type_name == "slice" || type_name == "string"
}

func drop_function_name(dtor_impl impl) string {
    if impl.function_name != "" { return impl.function_name }
    "__s_drop_" + impl.type_name
}

func check_field_move(dtor_registry registry, string type_name, string field_name) dtor_check_result {
    index := dtor_registry_find(registry, type_name)
    if index >= 0 && registry.impls[index].custom {
        return dtor_check_result {
            ok: false,
            message: "cannot move field '" + field_name + "' from Drop type '" + type_name + "'",
        }
    }
    dtor_check_result { ok: true, message: "" }
}

func emit_drop_call(dtor_registry registry, string var_name, string type_name) string {
    index := dtor_registry_find(registry, type_name)
    function_name := "__s_drop_" + type_name
    if index >= 0 { function_name = drop_function_name(registry.impls[index]) }
    function_name + "(&" + var_name + ")"
}

func emit_scope_cleanup(dtor_registry registry, string[] vars, string[] types) string[] {
    string[] cleanup
    i := len(vars) - 1
    for i >= 0 {
        if i < len(types) && dtor_registry_needs_drop(registry, types[i]) {
            cleanup = append(cleanup, emit_drop_call(registry, vars[i], types[i]))
        }
        i = i - 1
    }
    cleanup
}

func generate_c_drop_stub(dtor_impl impl) string {
    function_name := drop_function_name(impl)
    code := "static void " + function_name + "(" + impl.type_name + " *value) {\n"
    code = code + "    if (value == 0) return;\n"
    i := len(impl.fields) - 1
    for i >= 0 {
        field := impl.fields[i]
        if field.needs_drop {
            code = code + "    __s_drop_" + field.type_name + "(&value->" + field.name + ");\n"
        }
        i = i - 1
    }
    code + "}\n"
}

func starts_with(string text, string prefix) bool {
    if len(prefix) > len(text) { return false }
    slice(text, 0, len(prefix)) == prefix
}

func ends_with(string text, string suffix) bool {
    if len(suffix) > len(text) { return false }
    slice(text, len(text) - len(suffix), len(text)) == suffix
}
