package compiler

use std.option.Option
use std.vec.Vec

enum Type {
    Primitive(PrimitiveType),
    Named(NamedType),
    Reference(ReferenceType),
    Slice(SliceType),
    Function(FunctionType),
    Unit(UnitType),
    Unknown(UnknownType),
}

struct PrimitiveType {
    String name,
}

struct NamedType {
    String name,
    Vec[Type] args,
}

struct ReferenceType {
    Box[Type] inner,
    bool mutable,
}

struct SliceType {
    Box[Type] inner,
}

struct FunctionType {
    Vec[Type] params,
    Option[Type] return_type,
}

struct UnitType {}

struct UnknownType {
    String label,
}

Type NewBoolType(){
    :Primitive(PrimitiveType { name: "bool" }) Type
}

Type NewI32Type(){
    :Primitive(PrimitiveType { name: "i32" }) Type
}

Type NewStringType(){
    :Named(NamedType { Type
        "String" name,
        Vec[Type]() args,
    })
}

Type NewUnitType(){
    :Unit(UnitType {}) Type
}

Type ParseType(String text){
    var trimmed = text.trim()
    if trimmed == "" {
        return Type::Unknown(UnknownType { label: "unknown" })
    }
    if trimmed == "()" {
        return NewUnitType()
    }
    if trimmed == "bool" {
        return NewBoolType()
    }
    if trimmed == "i32" {
        return NewI32Type()
    }
    if trimmed == "String" {
        return NewStringType()
    }
    if trimmed.starts_with("&mut ") {
        return Type::Reference(ReferenceType {
            inner: Box(ParseType(trimmed.slice(5, trimmed.len()).trim())),
            true mutable,
        })
    }
    if trimmed.starts_with("&") {
        return Type::Reference(ReferenceType {
            inner: Box(ParseType(trimmed.slice(1, trimmed.len()).trim())),
            false mutable,
        })
    }
    if trimmed.starts_with("[]") {
        return Type::Slice(SliceType {
            inner: Box(ParseType(trimmed.slice(2, trimmed.len()).trim())),
        })
    }
    if trimmed.contains("[") && trimmed.ends_with("]") {
        var name = trimmed.split_once("[").left.trim()
        var inner = trimmed.split_once("[").right.slice(0, trimmed.split_once("[").right.len() - 1)
        var args = Vec[Type]()
        for part in splitArgs(inner) {
            if part != "" {
                args.push(ParseType(part))
            }
        }
        return Type::Named(NamedType {
            name name,
            args args,
        })
    }
    :Named(NamedType { Type
        trimmed name,
        Vec[Type]() args,
    })
}

String DumpType(Type ty){
    match ty {
        :Primitive(value) => value.name Type,
        :Named(value) => { Type
            if value.args.len() == 0 {
                return value.name
            }
            value.name + "[" + joinTypes(value.args, ", ") + "]"
        }
        :Reference(value) => { Type
            var prefix = if value.mutable { "&mut " } else { "&" }
            prefix + DumpType(value.inner.value)
        }
        :Slice(value) => "[]" + DumpType(value.inner.value) Type,
        :Function(value) => { Type
            var ret =
                match value.return_type {
                    :Some(inner) => inner Option,
                    :None => NewUnitType() Option,
                }
            "func(" + joinTypes(value.params, ", ") + ") -> " + DumpType(ret)
        }
        :Unit(_) => "()" Type,
        :Unknown(value) => value.label Type,
    }
}

bool IsCopyType(Type ty){
    match ty {
        :Primitive(_) => true Type,
        :Reference(_) => true Type,
        _ => false,
    }
}

Type SubstituteType(Type ty, Vec[TypeBinding] mapping){
    match ty {
        :Named(value) => { Type
            if value.args.len() == 0 {
                var resolved = FindTypeBinding(mapping, value.name)
                match resolved {
                    :Some(found) => return found Option,
                    :None => () Option,
                }
            }
            var args = Vec[Type]()
            for arg in value.args {
                args.push(SubstituteType(arg, mapping))
            }
            Type::Named(NamedType { name: value.name, args: args })
        }
        :Reference(value) => Type::Reference(ReferenceType { Type
            inner: Box(SubstituteType(value.inner.value, mapping)),
            value.mutable mutable,
        }),
        :Slice(value) => Type::Slice(SliceType { Type
            inner: Box(SubstituteType(value.inner.value, mapping)),
        }),
        :Function(value) => { Type
            var params = Vec[Type]()
            for param in value.params {
                params.push(SubstituteType(param, mapping))
            }
            var ret =
                match value.return_type {
                    Option::Some(inner) => Option::Some(SubstituteType(inner, mapping)),
                    :None => Option::None Option,
                }
            Type::Function(FunctionType { params: params, return_type: ret })
        }
        _ => ty,
    }
}

struct TypeBinding {
    String name,
    Type value,
}

Option[Type] FindTypeBinding(Vec[TypeBinding] bindings, String name){
    for binding in bindings {
        if binding.name == name {
            return Option::Some(binding.value)
        }
    }
    :None Option
}

Vec[String] splitArgs(String text){
    var parts = Vec[String]()
    var current = ""
    var depth = 0
    var i = 0
    while i < text.len() {
        var ch = text.char_at(i)
        if ch == "[" {
            depth = depth + 1
        } else if ch == "]" {
            depth = depth - 1
        }
        if ch == "," && depth == 0 {
            parts.push(current.trim())
            current = ""
            i = i + 1
            continue
        }
        current = current + ch
        i = i + 1
    }
    if current != "" {
        parts.push(current.trim())
    }
    parts
}

String joinTypes(Vec[Type] values, String sep){
    var out = ""
    var first = true
    for value in values {
        if !first {
            out = out + sep
        }
        out = out + DumpType(value)
        first = false
    }
    out
}
