package compile.internal.mono
use compile.internal.typesys.is_copy_type
use compile.internal.typesys.ownership_mode
use compile.internal.typesys.requires_drop
use s.function_decl
use s.function_sig
use s.param
use std.option.option

struct generic_instance_key {
    string function_name
    string[] type_args
}

struct mono_instance {
    string generic_name
    string instance_name
    string[] type_args
}

struct mono_cache {
    mono_instance[] instances
}

struct mono_cache_result {
    mono_cache cache
    string instance_name
}

struct mono_ownership_summary {
    string type_name
    string ownership
    bool copy
    bool drop
}

struct mono_function_summary {
    string instance_name
    mono_ownership_summary[] params
    mono_ownership_summary result
}

func new_cache() mono_cache {
    mono_cache { instances: mono_instance[] {} }
}

func make_instance_key(string generic_name, string[] type_args) generic_instance_key {
    generic_instance_key { function_name: generic_name, type_args: type_args }
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

func mono_cache_lookup(mono_cache cache, string generic_name, string[] type_args) string {
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

func mono_cache_lookup_key(mono_cache cache, generic_instance_key key) string {
    mono_cache_lookup(cache, key.function_name, key.type_args)
}

func mono_cache_get_or_create(mono_cache cache, string generic_name, string[] type_args) mono_cache_result {
    existing := mono_cache_lookup(cache, generic_name, type_args)
    if existing != "" { return mono_cache_result { cache: cache, instance_name: existing } }
    name := make_instance_name(generic_name, type_args)
    cache.instances = append(cache.instances, mono_instance {
        generic_name: generic_name,
        instance_name: name,
        type_args: type_args,
    })
    mono_cache_result { cache: cache, instance_name: name }
}

func mono_cache_get_or_create_key(mono_cache cache, generic_instance_key key) mono_cache_result {
    mono_cache_get_or_create(cache, key.function_name, key.type_args)
}

func mono_cache_count(mono_cache cache) int {
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
    generic_names := string[] {}
    i := 0
    for i < len(source.sig.generics) {
        raw := source.sig.generics[i]
        colon := find_char(raw, ":")
        if colon >= 0 { raw = slice(raw, 0, colon) }
        generic_names = append(generic_names, raw)
        i = i + 1
    }
    params := param[] {}
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
    if source.sig.return_type.is_some() {
        return_type = option.some(substitute_type(source.sig.return_type.unwrap(), generic_names, type_args))
    }
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

func summarize_type(string type_name) mono_ownership_summary {
    mono_ownership_summary {
        type_name: type_name,
        ownership: ownership_mode(type_name),
        copy: is_copy_type(type_name),
        drop: requires_drop(type_name),
    }
}

func summarize_instance(function_decl instance) mono_function_summary {
    params := mono_ownership_summary[] {}
    i := 0
    for i < len(instance.sig.params) {
        params = append(params, summarize_type(instance.sig.params[i].type_name))
        i = i + 1
    }
    result := summarize_type("()")
    if instance.sig.return_type.is_some() {
        result = summarize_type(instance.sig.return_type.unwrap())
    }
    mono_function_summary { instance_name: instance.sig.name, params: params, result: result }
}
