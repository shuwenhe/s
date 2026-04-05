package compiler

use std.option.Option
use std.vec.Vec

pub struct BuiltinMethodDecl {
    name: String,
    trait_name: Option[String],
    receiver_mode: String,
    receiver_policy: String,
    signature: FunctionType,
}

pub struct BuiltinFieldDecl {
    name: String,
    ty: Type,
    visibility: String,
    readable: bool,
    writable: bool,
}

pub struct BuiltinTraitDecl {
    name: String,
    methods: Vec[BuiltinMethodGroup],
}

pub struct BuiltinMethodGroup {
    name: String,
    overloads: Vec[BuiltinMethodDecl],
}

pub struct BuiltinTypeDecl {
    name: String,
    traits: Vec[String],
    fields: Vec[BuiltinFieldDecl],
    methods: Vec[BuiltinMethodGroup],
    index_result_kind: Option[String],
    default_impls: Vec[String],
}

pub struct BuiltinModuleDecl {
    name: String,
    traits: Vec[BuiltinTraitDecl],
    types: Vec[BuiltinTypeDecl],
}

pub fn load_prelude() -> BuiltinModuleDecl {
    BuiltinModuleDecl {
        name: "std.prelude",
        traits: built_in_traits(),
        types: built_in_types(),
    }
}

pub fn built_in_traits() -> Vec[BuiltinTraitDecl] {
    let traits = Vec[BuiltinTraitDecl]()
    traits.push(BuiltinTraitDecl {
        name: "Len",
        methods: Vec[BuiltinMethodGroup] {
            BuiltinMethodGroup {
                name: "len",
                overloads: Vec[BuiltinMethodDecl] {
                    make_method("len", Option::None, "ref", Vec[Type](), i32_type()),
                },
            },
        },
    })
    traits.push(BuiltinTraitDecl {
        name: "Push",
        methods: Vec[BuiltinMethodGroup] {
            BuiltinMethodGroup {
                name: "push",
                overloads: Vec[BuiltinMethodDecl] {
                    make_method("push", Option::None, "mut", Vec[Type] { named_type("T") }, unit_type()),
                },
            },
        },
    })
    traits
}

pub fn built_in_types() -> Vec[BuiltinTypeDecl] {
    let types = Vec[BuiltinTypeDecl]()
    types.push(BuiltinTypeDecl {
        name: "String",
        traits: Vec[String] { "Clone" },
        fields: Vec[BuiltinFieldDecl](),
        methods: Vec[BuiltinMethodGroup] {
            BuiltinMethodGroup {
                name: "len",
                overloads: Vec[BuiltinMethodDecl] {
                    make_method("len", Option::Some("Len"), "ref", Vec[Type](), i32_type()),
                },
            },
        },
        index_result_kind: Option::None,
        default_impls: Vec[String] { "Len" },
    })
    types.push(BuiltinTypeDecl {
        name: "Vec",
        traits: Vec[String] { "Clone" },
        fields: Vec[BuiltinFieldDecl](),
        methods: Vec[BuiltinMethodGroup] {
            BuiltinMethodGroup {
                name: "len",
                overloads: Vec[BuiltinMethodDecl] {
                    make_method("len", Option::Some("Len"), "ref", Vec[Type](), i32_type()),
                },
            },
            BuiltinMethodGroup {
                name: "push",
                overloads: Vec[BuiltinMethodDecl] {
                    make_method("push", Option::Some("Push"), "mut", Vec[Type] { named_type("T") }, unit_type()),
                },
            },
        },
        index_result_kind: Option::Some("first_type_arg"),
        default_impls: Vec[String] { "Len", "Push" },
    })
    types.push(BuiltinTypeDecl {
        name: "FileInfo",
        traits: Vec[String](),
        fields: Vec[BuiltinFieldDecl] {
            BuiltinFieldDecl {
                name: "size",
                ty: i32_type(),
                visibility: "pub",
                readable: true,
                writable: false,
            },
            BuiltinFieldDecl {
                name: "hidden",
                ty: i32_type(),
                visibility: "priv",
                readable: false,
                writable: false,
            },
        },
        methods: Vec[BuiltinMethodGroup](),
        index_result_kind: Option::None,
        default_impls: Vec[String](),
    })
    types
}

pub fn prelude() -> BuiltinModuleDecl {
    load_prelude()
}

pub fn lookup_builtin_type(receiver_type: Type) -> Option[BuiltinTypeDecl] {
    let base = base_name(receiver_type)
    match base {
        Option::Some(name) => find_builtin_type(built_in_types(), name),
        Option::None => Option::None,
    }
}

pub fn lookup_builtin_methods(receiver_type: Type, member: String) -> Vec[BuiltinMethodDecl] {
    match lookup_builtin_type(receiver_type) {
        Option::Some(builtin_type) => find_builtin_methods(builtin_type, member, receiver_type),
        Option::None => Vec[BuiltinMethodDecl](),
    }
}

pub fn lookup_builtin_method(receiver_type: Type, member: String) -> Option[BuiltinMethodDecl] {
    let methods = lookup_builtin_methods(receiver_type, member)
    if methods.len() == 1 {
        return Option::Some(methods[0])
    }
    Option::None
}

pub fn lookup_index_type(receiver_type: Type) -> Option[Type] {
    let inner = unwrap_refs(receiver_type)
    match lookup_builtin_type(inner) {
        Option::Some(builtin_type) => {
            match builtin_type.index_result_kind {
                Option::Some(kind) => {
                    if kind == "first_type_arg" {
                        match inner {
                            Type::Named(value) => {
                                if value.args.len() > 0 {
                                    return Option::Some(value.args[0])
                                }
                            }
                            _ => (),
                        }
                    }
                }
                Option::None => (),
            }
        }
        Option::None => (),
    }
    match inner {
        Type::Slice(value) => Option::Some(value.inner.value),
        _ => Option::None,
    }
}

pub fn find_builtin_type(types: Vec[BuiltinTypeDecl], name: String) -> Option[BuiltinTypeDecl] {
    for ty in types {
        if ty.name == name {
            return Option::Some(ty)
        }
    }
    Option::None
}

pub fn find_builtin_methods(
    builtin_type: BuiltinTypeDecl,
    member: String,
    receiver_type: Type,
) -> Vec[BuiltinMethodDecl] {
    for method_group in builtin_type.methods {
        if method_group.name == member {
            if builtin_type.name == "Vec" && member == "push" {
                return rewrite_vec_push(method_group.overloads, receiver_type)
            }
            return method_group.overloads
        }
    }
    Vec[BuiltinMethodDecl]()
}

pub fn rewrite_vec_push(methods: Vec[BuiltinMethodDecl], receiver_type: Type) -> Vec[BuiltinMethodDecl] {
    let rewritten = Vec[BuiltinMethodDecl]()
    let inner = unwrap_refs(receiver_type)
    let replacement = first_named_arg(inner)
    for method in methods {
        match replacement {
            Option::Some(value) => {
                let params = Vec[Type]()
                let index = 0
                for param in method.signature.params {
                    if index == 0 && is_named_type_var(param, "T") {
                        params.push(value)
                    } else {
                        params.push(param)
                    }
                    index = index + 1
                }
                rewritten.push(BuiltinMethodDecl {
                    name: method.name,
                    trait_name: method.trait_name,
                    receiver_mode: method.receiver_mode,
                    receiver_policy: method.receiver_policy,
                    signature: FunctionType {
                        params: params,
                        return_type: method.signature.return_type,
                    },
                })
            }
            Option::None => rewritten.push(method),
        }
    }
    rewritten
}

pub fn first_named_arg(ty: Type) -> Option[Type] {
    match ty {
        Type::Named(value) => {
            if value.args.len() > 0 {
                return Option::Some(value.args[0])
            }
            Option::None
        }
        _ => Option::None,
    }
}

pub fn is_named_type_var(ty: Type, name: String) -> bool {
    match ty {
        Type::Named(value) => value.name == name && value.args.len() == 0,
        _ => false,
    }
}

pub fn unwrap_refs(ty: Type) -> Type {
    let current = ty
    while true {
        match current {
            Type::Reference(value) => current = value.inner.value,
            _ => return current,
        }
    }
    current
}

pub fn base_name(ty: Type) -> Option[String] {
    match unwrap_refs(ty) {
        Type::Named(value) => Option::Some(value.name),
        _ => Option::None,
    }
}

pub fn named_type(name: String) -> Type {
    Type::Named(NamedType {
        name: name,
        args: Vec[Type](),
    })
}

pub fn make_method(
    name: String,
    trait_name: Option[String],
    receiver_mode: String,
    params: Vec[Type],
    return_type: Type,
) -> BuiltinMethodDecl {
    BuiltinMethodDecl {
        name: name,
        trait_name: trait_name,
        receiver_mode: receiver_mode,
        receiver_policy: receiver_policy_for(receiver_mode),
        signature: FunctionType {
            params: params,
            return_type: Option::Some(return_type),
        },
    }
}

pub fn receiver_policy_for(receiver_mode: String) -> String {
    if receiver_mode == "mut" {
        return "addressable"
    }
    "shared_or_addressable"
}
