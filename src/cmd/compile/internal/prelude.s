package compile.internal.prelude

use compile.internal.typesys.base_type_name

func load_prelude() int32 {
    0
}

func lookup_builtin_type(string name) bool {
    var base = base_type_name(name)
    base == "string"
        || base == "Vec"
        || base == "Result"
        || base == "Option"
        || base == "Box"
        || base == "Array"
        || base == "FileInfo"
        || base == "Path"
        || base == "CompileOptions"
        || base == "ParseError"
        || base == "ExecError"
        || base == "BuildCfg"
        || base == "BuildCfgError"
        || base == "Target"
        || base == "Toolchain"
}

func lookup_builtin_field_type(string type_name, string field_name) string {
    var base = base_type_name(type_name)
    if base == "FileInfo" {
        if field_name == "size" || field_name == "hidden" {
            return "int32"
        }
    }
    if base == "Target" {
        if field_name == "os" || field_name == "arch" {
            return "string"
        }
    }
    ""
}

func lookup_builtin_index_type(string type_name) string {
    var base = base_type_name(type_name)
    if base == "Vec" || base == "Array" {
        return "firstTypeArg"
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
    if base == "string" && member == "isEmpty" {
        return "bool"
    }
    if base == "Vec" && member == "len" {
        return "int32"
    }
    if base == "Vec" && member == "push" {
        return "()"
    }
    if base == "Vec" && member == "pop" {
        return "Option[T]"
    }
    if base == "Vec" && member == "clear" {
        return "()"
    }
    if base == "Vec" && member == "set" {
        return "bool"
    }
    if base == "Result" && member == "isOk" {
        return "bool"
    }
    if base == "Result" && member == "isErr" {
        return "bool"
    }
    if base == "Result" && member == "unwrap" {
        return "T"
    }
    if base == "Result" && member == "unwrapErr" {
        return "E"
    }
    if base == "Option" && member == "isSome" {
        return "bool"
    }
    if base == "Option" && member == "isNone" {
        return "bool"
    }
    if base == "Option" && member == "unwrap" {
        return "T"
    }
    if base == "Box" && member == "unwrap" {
        return "T"
    }
    ""
}

func lookup_builtin_method_arity(string type_name, string member) int32 {
    var base = base_type_name(type_name)
    if base == "Vec" && member == "push" {
        return 1
    }
    if base == "Vec" && (member == "set") {
        return 2
    }
    if base == "Vec" && (member == "pop" || member == "clear" || member == "len") {
        return 0
    }
    if base == "Result" && (member == "unwrap" || member == "unwrapErr" || member == "isOk" || member == "isErr") {
        return 0
    }
    if base == "Option" && (member == "unwrap" || member == "isSome" || member == "isNone") {
        return 0
    }
    if base == "Box" && member == "unwrap" {
        return 0
    }
    if (base == "string" || base == "Vec") && member == "len" {
        return 0
    }
    if base == "string" && member == "isEmpty" {
        return 0
    }
    0 - 1
}
