package compile.internal.mono
use s.function_decl
use s.function_sig
use s.param
use std.option.option

struct mono_instance {
    string generic_name
    string instance_name
    string[] type_args
}

struct mono_cache {
    mono_instance[] instances
}

func new_cache() mono_cache {
    mono_cache { instances: mono_instance[] {} }
}

func make_instance_name(string generic_name, string[] type_args) string {
    name := generic_name + "__mono"
    i := 0
    for i < len(type_args) {
        name = name + "_" + encode_type(type_args[i])
        i = i + 1
    }
    name
}

func encode_type(string type_name) string {
    out := ""
    i := 0
    for i < len(type_name) {
        ch := string(type_name[i])
        if ch == "&" { out = out + "ref"
        } else if ch == "[" { out = out + "arr"
        } else if ch == "]" { out = out + "end"
        } else if ch == "," || ch == " " { out = out + "_"
        } else { out = out + ch }
        i = i + 1
    }
    if out == "" { return "unknown" }
    out
}

func same_type_args(string[] left, string[] right) bool {
    if len(left) != len(right) { return false }
    i := 0
    for i < len(left) {
        if left[i] != right[i] { return false }
        i = i + 1
    }
    true
}

func (mono_cache* cache) lookup(string generic_name, string[] type_args) string {
    i := 0
    for i < len(cache.instances) {
        instance := cache.instances[i]
        if instance.generic_name == generic_name && same_type_args(instance.type_args, type_args) {
            return instance.instance_name
        }
        i = i + 1
    }
    ""
}

func (mono_cache* cache) get_or_create(string generic_name, string[] type_args) string {
    existing := cache.lookup(generic_name, type_args)
    if existing != "" { return existing }
    name := make_instance_name(generic_name, type_args)
    cache.instances = append(cache.instances, mono_instance {
        generic_name: generic_name,
        instance_name: name,
        type_args: type_args,
    })
    name
}

func (mono_cache* cache) count() int {
    len(cache.instances)
}

func substitute_type(string type_name, string[] generic_names, string[] type_args) string {
    i := 0
    for i < len(generic_names) {
        if type_name == generic_names[i] {
            if i < len(type_args) { return type_args[i] }
            return "unknown"
        }
        if len(type_name) > len(generic_names[i]) &&
            slice(type_name, 0, len(generic_names[i])) == generic_names[i] {
            suffix := slice(type_name, len(generic_names[i]), len(type_name))
            if len(suffix) > 0 && (suffix == "[]" || suffix == "[" || suffix == "*") {
                if i < len(type_args) {
                    return type_args[i]
                }
            }
        }
        i = i + 1
    }
    type_name
}

func find_char(string text, string needle) int {
    i := 0
    for i < len(text) {
        if string(text[i]) == needle { return i }
        i = i + 1
    }
    -1
}

func specialize_function(function_decl source, string[] type_args) function_decl {
    string[] generic_names
    i := 0
    for i < len(source.sig.generics) {
        raw := source.sig.generics[i]
        colon := find_char(raw, ":")
        if colon >= 0 { raw = slice(raw, 0, colon) }
        generic_names = append(generic_names, raw)
        i = i + 1
    }
    param[] params
    i = 0
    for i < len(source.sig.params) {
        original := source.sig.params[i]
        params = append(params, param {
            name: original.name,
            type_name: substitute_type(original.type_name, generic_names, type_args),
        })
        i = i + 1
    }
    return_type := source.sig.return_type
    function_decl {
        sig: function_sig {
            name: make_instance_name(source.sig.name, type_args),
            generics: string[] {},
            params: params,
            return_type: return_type,
        },
        body: source.body,
        is_public: source.is_public,
    }
}
