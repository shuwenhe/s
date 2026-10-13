package compile.internal.walk

struct builtin_plan {
    string name
    string runtime_name
    int arg_count
    bool needs_runtime
    bool preserves_length
}

func builtin_module_name() string {
    "walk/builtin.s"
}

func builtin_module_apply() int {
    0
}

func walk_builtin_plan(string name, int arg_count) builtin_plan {
    builtin_plan {
        name: name,
        runtime_name: builtin_runtime_name(name),
        arg_count: arg_count,
        needs_runtime: builtin_needs_runtime(name),
        preserves_length: name == "len" || name == "cap",
    }
}

func builtin_needs_runtime(string name) bool {
    name == "append" || name == "copy" || name == "delete" || name == "clear"
        || name == "make" || name == "new" || name == "panic" || name == "recover"
}

func builtin_runtime_name(string name) string {
    if name == "append" {
        return "growslice"
    }
    if name == "copy" {
        return "slicecopy"
    }
    if name == "delete" {
        return "mapdelete"
    }
    if name == "clear" {
        return "memclr"
    }
    if name == "make" {
        return "makeslice"
    }
    if name == "new" {
        return "newobject"
    }
    name
}

func builtin_is_len_cap(string name) bool {
    name == "len" || name == "cap"
}
