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

func LookupBuiltinFieldType(string typeName, string fieldName) string {
    var base = BaseTypeName(typeName)
    if base == "FileInfo" {
        if fieldName == "size" || fieldName == "hidden" {
            return "int32"
        }
    }
    if base == "Target" {
        if fieldName == "os" || fieldName == "arch" {
            return "string"
        }
    }
    ""
}

func LookupBuiltinIndexType(string typeName) string {
    var base = BaseTypeName(typeName)
    if base == "Vec" || base == "Array" {
        return "firstTypeArg"
    }
    if base == "string" {
        return "u8"
    }
    ""
}

func LookupBuiltinMethodType(string typeName, string member) string {
    var base = BaseTypeName(typeName)
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

func LookupBuiltinMethodArity(string typeName, string member) int32 {
    var base = BaseTypeName(typeName)
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
