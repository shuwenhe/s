package compile.internal

struct convert_plan {
    string source_kind
    string target_kind
    string runtime_name
    bool needs_runtime
    bool needs_temp
}

func walk_convert_module_name() string {
    "walk/convert.s"
}

func walk_convert_module_apply() int {
    0
}

func walk_convert_plan(string source_kind, string target_kind) convert_plan {
    convert_plan {
        source_kind: source_kind,
        target_kind: target_kind,
        runtime_name: convert_runtime_name(source_kind, target_kind),
        needs_runtime: convert_needs_runtime(source_kind, target_kind),
        needs_temp: convert_needs_temp(source_kind, target_kind),
    }
}

func convert_needs_runtime(string source_kind, string target_kind) bool {
    source_kind == "string" && target_kind == "[]byte"
        || source_kind == "[]byte" && target_kind == "string"
        || source_kind == "[]rune" && target_kind == "string"
        || target_kind == "interface"
}

func convert_needs_temp(string source_kind, string target_kind) bool {
    source_kind == "string" && target_kind == "[]byte"
}

func convert_runtime_name(string source_kind, string target_kind) string {
    if source_kind == "string" && target_kind == "[]byte" { return "stringtoslicebyte" }
    if source_kind == "[]byte" && target_kind == "string" { return "slicebytetostring" }
    if source_kind == "[]rune" && target_kind == "string" { return "slicerunetostring" }
    if target_kind == "interface" { return "convT" }
    ""
}
