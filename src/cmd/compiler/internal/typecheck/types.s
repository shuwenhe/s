package compiler.internal.typecheck

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

func NewBoolType() -> Type {
    Type::Primitive(PrimitiveType { name: "bool" })
}

func NewI32Type() -> Type {
    Type::Primitive(PrimitiveType { name: "i32" })
}

func NewStringType() -> Type {
    Type::Named(NamedType {
        name: "String",
        args: Vec[Type](),
    })
}

func NewUnitType() -> Type {
    Type::Unit(UnitType {})
}

func UnknownTypeOf(String label) -> Type {
    Type::Unknown(UnknownType { label: label })
}

func ParseType(String text) -> Type {
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
            mutable: true,
        })
    }
    if trimmed.starts_with("&") {
        return Type::Reference(ReferenceType {
            inner: Box(ParseType(trimmed.slice(1, trimmed.len()).trim())),
            mutable: false,
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
            name: name,
            args: args,
        })
    }
    Type::Named(NamedType {
        name: trimmed,
        args: Vec[Type](),
    })
}

func DumpType(Type ty) -> String {
    match ty {
        Type::Primitive(value) => value.name,
        Type::Named(value) => {
            if value.args.len() == 0 {
                return value.name
            }
            value.name + "[" + joinTypes(value.args, ", ") + "]"
        }
        Type::Reference(value) => {
            var prefix = if value.mutable { "&mut " } else { "&" }
            prefix + DumpType(value.inner.value)
        }
        Type::Slice(value) => "[]" + DumpType(value.inner.value),
        Type::Function(value) => {
            var ret =
                match value.return_type {
                    Option::Some(inner) => inner,
                    Option::None => NewUnitType(),
                }
            "func(" + joinTypes(value.params, ", ") + ") -> " + DumpType(ret)
        }
        Type::Unit(_) => "()",
        Type::Unknown(value) => value.label,
    }
}

func IsCopyType(Type ty) -> bool {
    match ty {
        Type::Primitive(_) => true,
        Type::Reference(_) => true,
        _ => false,
    }
}

func IsNamedTypeVar(Type ty, String name) -> bool {
    match ty {
        Type::Named(value) => value.name == name && value.args.len() == 0,
        _ => false,
    }
}

func UnwrapRefs(Type ty) -> Type {
    match ty {
        Type::Reference(value) => UnwrapRefs(value.inner.value),
        _ => ty,
    }
}

func SubstituteType(Type ty, Vec[TypeBinding] mapping) -> Type {
    match ty {
        Type::Named(value) => {
            if value.args.len() == 0 {
                var resolved = FindTypeBinding(mapping, value.name)
                match resolved {
                    Option::Some(found) => return found,
                    Option::None => (),
                }
            }
            var args = Vec[Type]()
            for arg in value.args {
                args.push(SubstituteType(arg, mapping))
            }
            Type::Named(NamedType { name: value.name, args: args })
        }
        Type::Reference(value) => Type::Reference(ReferenceType {
            inner: Box(SubstituteType(value.inner.value, mapping)),
            mutable: value.mutable,
        }),
        Type::Slice(value) => Type::Slice(SliceType {
            inner: Box(SubstituteType(value.inner.value, mapping)),
        }),
        Type::Function(value) => {
            var params = Vec[Type]()
            for param in value.params {
                params.push(SubstituteType(param, mapping))
            }
            var ret =
                match value.return_type {
                    Option::Some(inner) => Option::Some(SubstituteType(inner, mapping)),
                    Option::None => Option::None,
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

func FindTypeBinding(Vec[TypeBinding] bindings, String name) -> Option[Type] {
    for binding in bindings {
        if binding.name == name {
            return Option::Some(binding.value)
        }
    }
    Option::None
}

func splitArgs(String text) -> Vec[String] {
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

func joinTypes(Vec[Type] values, String sep) -> String {
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
