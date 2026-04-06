package compiler

use compiler.internal.typecheck.FindTypeBinding
use compiler.internal.typecheck.FunctionType
use compiler.internal.typecheck.IsNamedTypeVar
use compiler.internal.typecheck.NamedType
use compiler.internal.typecheck.NewBoolType
use compiler.internal.typecheck.NewI32Type
use compiler.internal.typecheck.NewStringType
use compiler.internal.typecheck.NewUnitType
use compiler.internal.typecheck.ParseType
use compiler.internal.typecheck.ReferenceType
use compiler.internal.typecheck.SliceType
use compiler.internal.typecheck.Type
use compiler.internal.typecheck.TypeBinding
use compiler.internal.typecheck.UnwrapRefs
use std.option.Option
use std.vec.Vec

struct BuiltinMethodDecl {
    String name,
    Option[String] trait_name,
    String receiver_mode,
    String receiver_policy,
    FunctionType signature,
}

struct BuiltinFieldDecl {
    String name,
    Type ty,
    String visibility,
    bool readable,
    bool writable,
}

struct BuiltinTraitDecl {
    String name,
    Vec[BuiltinMethodGroup] methods,
}

struct BuiltinMethodGroup {
    String name,
    Vec[BuiltinMethodDecl] overloads,
}

struct BuiltinTypeDecl {
    String name,
    Vec[String] traits,
    Vec[BuiltinFieldDecl] fields,
    Vec[BuiltinMethodGroup] methods,
    Option[String] index_result_kind,
    Vec[String] default_impls,
}

struct BuiltinModuleDecl {
    String name,
    Vec[BuiltinTraitDecl] traits,
    Vec[BuiltinTypeDecl] types,
}

func LoadPrelude() -> BuiltinModuleDecl {
    BuiltinModuleDecl {
        name: "std.prelude",
        traits: builtInTraits(),
        types: builtInTypes(),
    }
}

func builtInTraits() -> Vec[BuiltinTraitDecl] {
    var traits = Vec[BuiltinTraitDecl]()
    traits.push(BuiltinTraitDecl {
        name: "Len",
        methods: Vec[BuiltinMethodGroup] {
            BuiltinMethodGroup {
                name: "len",
                overloads: Vec[BuiltinMethodDecl] {
                    makeMethod("len", Option::None, "ref", Vec[Type](), NewI32Type()),
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
                    makeMethod("push", Option::None, "mut", Vec[Type] { namedType("T") }, NewUnitType()),
                },
            },
        },
    })
    traits
}

func builtInTypes() -> Vec[BuiltinTypeDecl] {
    var types = Vec[BuiltinTypeDecl]()
    types.push(BuiltinTypeDecl {
        name: "String",
        traits: Vec[String] { "Clone" },
        fields: Vec[BuiltinFieldDecl](),
        methods: Vec[BuiltinMethodGroup] {
            BuiltinMethodGroup {
                name: "len",
                overloads: Vec[BuiltinMethodDecl] {
                    makeMethod("len", Option::Some("Len"), "ref", Vec[Type](), NewI32Type()),
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
                    makeMethod("len", Option::Some("Len"), "ref", Vec[Type](), NewI32Type()),
                },
            },
            BuiltinMethodGroup {
                name: "push",
                overloads: Vec[BuiltinMethodDecl] {
                    makeMethod("push", Option::Some("Push"), "mut", Vec[Type] { namedType("T") }, NewUnitType()),
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
                ty: NewI32Type(),
                visibility: "pub",
                readable: true,
                writable: false,
            },
            BuiltinFieldDecl {
                name: "hidden",
                ty: NewI32Type(),
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

func Prelude() -> BuiltinModuleDecl {
    LoadPrelude()
}

func LookupBuiltinType(Type receiver_type) -> Option[BuiltinTypeDecl] {
    var base = baseName(receiver_type)
    match base {
        Option::Some(name) => findBuiltinType(builtInTypes(), name),
        Option::None => Option::None,
    }
}

func LookupBuiltinMethods(Type receiver_type, String member) -> Vec[BuiltinMethodDecl] {
    match LookupBuiltinType(receiver_type) {
        Option::Some(builtin_type) => findBuiltinMethods(builtin_type, member, receiver_type),
        Option::None => Vec[BuiltinMethodDecl](),
    }
}

func LookupBuiltinMethod(Type receiver_type, String member) -> Option[BuiltinMethodDecl] {
    var methods = LookupBuiltinMethods(receiver_type, member)
    if methods.len() == 1 {
        return Option::Some(methods[0])
    }
    Option::None
}

func LookupIndexType(Type receiver_type) -> Option[Type] {
    var inner = UnwrapRefs(receiver_type)
    match LookupBuiltinType(inner) {
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

func findBuiltinType(Vec[BuiltinTypeDecl] types, String name) -> Option[BuiltinTypeDecl] {
    for ty in types {
        if ty.name == name {
            return Option::Some(ty)
        }
    }
    Option::None
}

func findBuiltinMethods(
    BuiltinTypeDecl builtin_type,
    String member,
    Type receiver_type
) -> Vec[BuiltinMethodDecl] {
    for method_group in builtin_type.methods {
        if method_group.name == member {
            if builtin_type.name == "Vec" && member == "push" {
                return rewriteVecPush(method_group.overloads, receiver_type)
            }
            return method_group.overloads
        }
    }
    Vec[BuiltinMethodDecl]()
}

func rewriteVecPush(Vec[BuiltinMethodDecl] methods, Type receiver_type) -> Vec[BuiltinMethodDecl] {
    var rewritten = Vec[BuiltinMethodDecl]()
    var inner = UnwrapRefs(receiver_type)
    var replacement = firstNamedArg(inner)
    for method in methods {
        match replacement {
            Option::Some(value) => {
                var params = Vec[Type]()
                var index = 0
                for param in method.signature.params {
                    if index == 0 && IsNamedTypeVar(param, "T") {
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

func firstNamedArg(Type ty) -> Option[Type] {
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

func IsNamedTypeVar(Type ty, String name) -> bool {
    match ty {
        Type::Named(value) => value.name == name && value.args.len() == 0,
        _ => false,
    }
}

func UnwrapRefs(Type ty) -> Type {
    var current = ty
    while true {
        match current {
            Type::Reference(value) => current = value.inner.value,
            _ => return current,
        }
    }
    current
}

func baseName(Type ty) -> Option[String] {
    match UnwrapRefs(ty) {
        Type::Named(value) => Option::Some(value.name),
        _ => Option::None,
    }
}

func namedType(String name) -> Type {
    Type::Named(NamedType {
        name: name,
        args: Vec[Type](),
    })
}

func makeMethod(
    String name,
    Option[String] trait_name,
    String receiver_mode,
    Vec[Type] params,
    Type return_type
) -> BuiltinMethodDecl {
    BuiltinMethodDecl {
        name: name,
        trait_name: trait_name,
        receiver_mode: receiver_mode,
        receiver_policy: receiverPolicyFor(receiver_mode),
        signature: FunctionType {
            params: params,
            return_type: Option::Some(return_type),
        },
    }
}

func receiverPolicyFor(String receiver_mode) -> String {
    if receiver_mode == "mut" {
        return "addressable"
    }
    "shared_or_addressable"
}
