package compile.internal.mono

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

func (cache* mono_cache) lookup(string generic_name, string[] type_args) string {
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

func (cache* mono_cache) get_or_create(string generic_name, string[] type_args) string {
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

func (cache* mono_cache) count() int {
    len(cache.instances)
}

func cache_get_or_create(mono_cache* cache, string generic_name, string[] type_args) string {
    cache.get_or_create(generic_name, type_args)
}

func cache_count(mono_cache* cache) int {
    cache.count()
}
