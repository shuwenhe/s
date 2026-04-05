package compiler

use std.option.Option
use std.vec.Vec

pub enum Type {
    Primitive(PrimitiveType),
    Named(NamedType),
    Reference(ReferenceType),
    Slice(SliceType),
    Function(FunctionType),
    Unit(UnitType),
    Unknown(UnknownType),
}

pub struct PrimitiveType {
    name: String,
}

pub struct NamedType {
    name: String,
    args: Vec[Type],
}

pub struct ReferenceType {
    inner: Box[Type],
    mutable: bool,
}

pub struct SliceType {
    inner: Box[Type],
}

pub struct FunctionType {
    params: Vec[Type],
    return_type: Option[Type],
}

pub struct UnitType {}

pub struct UnknownType {
    label: String,
}

pub fn bool_type() -> Type {
    Type::Primitive(PrimitiveType { name: "bool" })
}

pub fn i32_type() -> Type {
    Type::Primitive(PrimitiveType { name: "i32" })
}

pub fn string_type() -> Type {
    Type::Named(NamedType {
        name: "String",
        args: Vec[Type](),
    })
}

pub fn unit_type() -> Type {
    Type::Unit(UnitType {})
}

pub fn parse_type(text: String) -> Type {
    let trimmed = text.trim()
    if trimmed == "" {
        return Type::Unknown(UnknownType { label: "unknown" })
    }
    if trimmed == "()" {
        return unit_type()
    }
    if trimmed == "bool" {
        return bool_type()
    }
    if trimmed == "i32" {
        return i32_type()
    }
    if trimmed == "String" {
        return string_type()
    }
    if trimmed.starts_with("&mut ") {
        return Type::Reference(ReferenceType {
            inner: Box(parse_type(trimmed.slice(5, trimmed.len()).trim())),
            mutable: true,
        })
    }
    if trimmed.starts_with("&") {
        return Type::Reference(ReferenceType {
            inner: Box(parse_type(trimmed.slice(1, trimmed.len()).trim())),
            mutable: false,
        })
    }
    if trimmed.starts_with("[]") {
        return Type::Slice(SliceType {
            inner: Box(parse_type(trimmed.slice(2, trimmed.len()).trim())),
        })
    }
    if trimmed.contains("[") && trimmed.ends_with("]") {
        let name = trimmed.split_once("[").left.trim()
        let inner = trimmed.split_once("[").right.slice(0, trimmed.split_once("[").right.len() - 1)
        let args = Vec[Type]()
        for part in split_args(inner) {
            if part != "" {
                args.push(parse_type(part))
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

pub fn dump_type(ty: Type) -> String {
    match ty {
        Type::Primitive(value) => value.name,
        Type::Named(value) => {
            if value.args.len() == 0 {
                return value.name
            }
            value.name + "[" + join_types(value.args, ", ") + "]"
        }
        Type::Reference(value) => {
            let prefix = if value.mutable { "&mut " } else { "&" }
            prefix + dump_type(value.inner.value)
        }
        Type::Slice(value) => "[]" + dump_type(value.inner.value),
        Type::Function(value) => {
            let ret =
                match value.return_type {
                    Option::Some(inner) => inner,
                    Option::None => unit_type(),
                }
            "fn(" + join_types(value.params, ", ") + ") -> " + dump_type(ret)
        }
        Type::Unit(_) => "()",
        Type::Unknown(value) => value.label,
    }
}

pub fn is_copy_type(ty: Type) -> bool {
    match ty {
        Type::Primitive(_) => true,
        Type::Reference(_) => true,
        _ => false,
    }
}

pub fn substitute_type(ty: Type, mapping: Vec[TypeBinding]) -> Type {
    match ty {
        Type::Named(value) => {
            if value.args.len() == 0 {
                let resolved = find_type_binding(mapping, value.name)
                match resolved {
                    Option::Some(found) => return found,
                    Option::None => (),
                }
            }
            let args = Vec[Type]()
            for arg in value.args {
                args.push(substitute_type(arg, mapping))
            }
            Type::Named(NamedType { name: value.name, args: args })
        }
        Type::Reference(value) => Type::Reference(ReferenceType {
            inner: Box(substitute_type(value.inner.value, mapping)),
            mutable: value.mutable,
        }),
        Type::Slice(value) => Type::Slice(SliceType {
            inner: Box(substitute_type(value.inner.value, mapping)),
        }),
        Type::Function(value) => {
            let params = Vec[Type]()
            for param in value.params {
                params.push(substitute_type(param, mapping))
            }
            let ret =
                match value.return_type {
                    Option::Some(inner) => Option::Some(substitute_type(inner, mapping)),
                    Option::None => Option::None,
                }
            Type::Function(FunctionType { params: params, return_type: ret })
        }
        _ => ty,
    }
}

pub struct TypeBinding {
    name: String,
    value: Type,
}

pub fn find_type_binding(bindings: Vec[TypeBinding], name: String) -> Option[Type] {
    for binding in bindings {
        if binding.name == name {
            return Option::Some(binding.value)
        }
    }
    Option::None
}

pub fn split_args(text: String) -> Vec[String] {
    let parts = Vec[String]()
    let current = ""
    let depth = 0
    let i = 0
    while i < text.len() {
        let ch = text.char_at(i)
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

pub fn join_types(values: Vec[Type], sep: String) -> String {
    let out = ""
    let first = true
    for value in values {
        if !first {
            out = out + sep
        }
        out = out + dump_type(value)
        first = false
    }
    out
}
