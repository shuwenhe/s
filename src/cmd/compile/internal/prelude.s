package compile.internal.prelude

use compile.internal.typesys.base_type_name

func load_prelude() int32 {
    0
}

func lookup_builtin_type(string name) bool {
    var base = base_type_name(name)
    base == "string"
        || base == "vec"
        || base == "result"
        || base == "option"
        || base == "box"
        || base == "array"
        || base == "file_info"
        || base == "path"
        || base == "compile_options"
        || base == "parse_error"
        || base == "exec_error"
        || base == "build_cfg"
        || base == "build_cfg_error"
        || base == "target"
        || base == "toolchain"
}

func lookup_builtin_field_type(string type_name, string field_name) string {
    var base = base_type_name(type_name)
    if base == "file_info" {
        if field_name == "size" || field_name == "hidden" {
            return "int32"
        }
    }
    if base == "target" {
        if field_name == "os" || field_name == "arch" {
            return "string"
        }
    }
    ""
}

func lookup_builtin_index_type(string type_name) string {
    var base = base_type_name(type_name)
    if base == "vec" || base == "array" {
        return "first_type_arg"
    }
    if base == "string" {
        return "u8"
    }
    ""
}

func lookup_builtin_method_type(string type_name, string member) string {
    var base = base_type_name(type_name)
    if base == "string" && member == "len" {
        return "int32"
    }
    if base == "string" && member == "is_empty" {
        return "bool"
    }
    if base == "vec" && member == "len" {
        return "int32"
    }
    if base == "vec" && member == "push" {
        return "()"
    }
    if base == "vec" && member == "pop" {
        return "option[t]"
    }
    if base == "vec" && member == "clear" {
        return "()"
    }
    if base == "vec" && member == "set" {
        return "bool"
    }
    if base == "result" && member == "is_ok" {
        return "bool"
    }
    if base == "result" && member == "is_err" {
        return "bool"
    }
    if base == "result" && member == "unwrap" {
        return "t"
    }
    if base == "result" && member == "unwrap_err" {
        return "e"
    }
    if base == "option" && member == "is_some" {
        return "bool"
    }
    if base == "option" && member == "is_none" {
        return "bool"
    }
    if base == "option" && member == "unwrap" {
        return "t"
    }
    if base == "box" && member == "unwrap" {
        return "t"
    }
    ""
}

func lookup_builtin_method_arity(string type_name, string member) int32 {
    var base = base_type_name(type_name)
    if base == "vec" && member == "push" {
        return 1
    }
    if base == "vec" && (member == "set") {
        return 2
    }
    if base == "vec" && (member == "pop" || member == "clear" || member == "len") {
        return 0
    }
    if base == "result" && (member == "unwrap" || member == "unwrap_err" || member == "is_ok" || member == "is_err") {
        return 0
    }
    if base == "option" && (member == "unwrap" || member == "is_some" || member == "is_none") {
        return 0
    }
    if base == "box" && member == "unwrap" {
        return 0
    }
    if (base == "string" || base == "vec") && member == "len" {
        return 0
    }
    if base == "string" && member == "is_empty" {
        return 0
    }
    0 - 1
}
