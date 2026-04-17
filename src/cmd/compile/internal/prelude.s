package compile.internal.prelude

use compile.internal.typesys.BaseTypeName

func LoadPrelude() int32 {
    0
}

func LookupBuiltinType(string name) bool {
    var base = BaseTypeName(name)
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

func LookupBuiltinFieldType(string type_name, string field_name) string {
    var base = BaseTypeName(type_name)
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

func LookupBuiltinIndexType(string type_name) string {
    var base = BaseTypeName(type_name)
    if base == "Vec" || base == "Array" {
        return "first_type_arg"
    }
    if base == "string" {
        return "u8"
    }
    ""
}

func LookupBuiltinMethodType(string type_name, string member) string {
    var base = BaseTypeName(type_name)
    if base == "string" && member == "len" {
        return "int32"
    }
    if base == "string" && member == "is_empty" {
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
    if base == "Result" && member == "is_ok" {
        return "bool"
    }
    if base == "Result" && member == "is_err" {
        return "bool"
    }
    if base == "Result" && member == "unwrap" {
        return "T"
    }
    if base == "Result" && member == "unwrap_err" {
        return "E"
    }
    if base == "Option" && member == "is_some" {
        return "bool"
    }
    if base == "Option" && member == "is_none" {
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

func LookupBuiltinMethodArity(string type_name, string member) int32 {
    var base = BaseTypeName(type_name)
    if base == "Vec" && member == "push" {
        return 1
    }
    if base == "Vec" && (member == "set") {
        return 2
    }
    if base == "Vec" && (member == "pop" || member == "clear" || member == "len") {
        return 0
    }
    if base == "Result" && (member == "unwrap" || member == "unwrap_err" || member == "is_ok" || member == "is_err") {
        return 0
    }
    if base == "Option" && (member == "unwrap" || member == "is_some" || member == "is_none") {
        return 0
    }
    if base == "Box" && member == "unwrap" {
        return 0
    }
    if (base == "string" || base == "Vec") && member == "len" {
        return 0
    }
    if base == "string" && member == "is_empty" {
        return 0
    }
    0 - 1
}
