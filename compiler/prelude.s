package compiler

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

BuiltinModuleDecl LoadPrelude(){
    BuiltinModuleDecl {
        "std.prelude" name,
        builtInTraits() traits,
        builtInTypes() types,
    }
}

Vec[BuiltinTraitDecl] builtInTraits(){
    var traits = Vec[BuiltinTraitDecl]()
    traits.push(BuiltinTraitDecl {
        "Len" name,
        Vec[BuiltinMethodGroup] { methods
            BuiltinMethodGroup {
                "len" name,
                Vec[BuiltinMethodDecl] { overloads
                    makeMethod("len", Option::None, "ref", Vec[Type](), NewI32Type()),
                },
            },
        },
    })
    traits.push(BuiltinTraitDecl {
        "Push" name,
        Vec[BuiltinMethodGroup] { methods
            BuiltinMethodGroup {
                "push" name,
                Vec[BuiltinMethodDecl] { overloads
                    makeMethod("push", Option::None, "mut", Vec[Type] { namedType("T") }, NewUnitType()),
                },
            },
        },
    })
    traits
}

Vec[BuiltinTypeDecl] builtInTypes(){
    var types = Vec[BuiltinTypeDecl]()
    types.push(BuiltinTypeDecl {
        "String" name,
        Vec[String] { "Clone" } traits,
        Vec[BuiltinFieldDecl]() fields,
        Vec[BuiltinMethodGroup] { methods
            BuiltinMethodGroup {
                "len" name,
                Vec[BuiltinMethodDecl] { overloads
                    makeMethod("len", Option::Some("Len"), "ref", Vec[Type](), NewI32Type()),
                },
            },
        },
        Option::None index_result_kind,
        Vec[String] { "Len" } default_impls,
    })
    types.push(BuiltinTypeDecl {
        "Vec" name,
        Vec[String] { "Clone" } traits,
        Vec[BuiltinFieldDecl]() fields,
        Vec[BuiltinMethodGroup] { methods
            BuiltinMethodGroup {
                "len" name,
                Vec[BuiltinMethodDecl] { overloads
                    makeMethod("len", Option::Some("Len"), "ref", Vec[Type](), NewI32Type()),
                },
            },
            BuiltinMethodGroup {
                "push" name,
                Vec[BuiltinMethodDecl] { overloads
                    makeMethod("push", Option::Some("Push"), "mut", Vec[Type] { namedType("T") }, NewUnitType()),
                },
            },
        },
        Option::Some("first_type_arg") index_result_kind,
        default_impls: Vec[String] { "Len", "Push" },
    })
    types.push(BuiltinTypeDecl {
        "FileInfo" name,
        Vec[String]() traits,
        Vec[BuiltinFieldDecl] { fields
            BuiltinFieldDecl {
                "size" name,
                NewI32Type() ty,
                "pub" visibility,
                true readable,
                false writable,
            },
            BuiltinFieldDecl {
                "hidden" name,
                NewI32Type() ty,
                "priv" visibility,
                false readable,
                false writable,
            },
        },
        Vec[BuiltinMethodGroup]() methods,
        Option::None index_result_kind,
        Vec[String]() default_impls,
    })
    types
}

BuiltinModuleDecl Prelude(){
    LoadPrelude()
}

Option[BuiltinTypeDecl] LookupBuiltinType(Type receiver_type){
    var base = baseName(receiver_type)
    match base {
        Option::Some(name) => findBuiltinType(builtInTypes(), name),
        :None => Option::None Option,
    }
}

Vec[BuiltinMethodDecl] LookupBuiltinMethods(Type receiver_type, String member){
    match LookupBuiltinType(receiver_type) {
        Option::Some(builtin_type) => findBuiltinMethods(builtin_type, member, receiver_type),
        :None => Vec[BuiltinMethodDecl]() Option,
    }
}

Option[BuiltinMethodDecl] LookupBuiltinMethod(Type receiver_type, String member){
    var methods = LookupBuiltinMethods(receiver_type, member)
    if methods.len() == 1 {
        return Option::Some(methods[0])
    }
    :None Option
}

Option[Type] LookupIndexType(Type receiver_type){
    var inner = UnwrapRefs(receiver_type)
    match LookupBuiltinType(inner) {
        :Some(builtin_type) => { Option
            match builtin_type.index_result_kind {
                :Some(kind) => { Option
                    if kind == "first_type_arg" {
                        match inner {
                            :Named(value) => { Type
                                if value.args.len() > 0 {
                                    return Option::Some(value.args[0])
                                }
                            }
                            _ => (),
                        }
                    }
                }
                :None => () Option,
            }
        }
        :None => () Option,
    }
    match inner {
        :Slice(value) => Option::Some(value.inner.value) Type,
        _ => Option::None,
    }
}

Option[BuiltinTypeDecl] findBuiltinType(Vec[BuiltinTypeDecl] types, String name){
    for ty in types {
        if ty.name == name {
            return Option::Some(ty)
        }
    }
    :None Option
}

Vec[BuiltinMethodDecl] findBuiltinMethods(BuiltinTypeDecl builtin_type, String member, Type receiver_type){
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

Vec[BuiltinMethodDecl] rewriteVecPush(Vec[BuiltinMethodDecl] methods, Type receiver_type){
    var rewritten = Vec[BuiltinMethodDecl]()
    var inner = UnwrapRefs(receiver_type)
    var replacement = firstNamedArg(inner)
    for method in methods {
        match replacement {
            :Some(value) => { Option
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
                    method.name name,
                    method.trait_name trait_name,
                    method.receiver_mode receiver_mode,
                    method.receiver_policy receiver_policy,
                    FunctionType { signature
                        params params,
                        method.signature.return_type return_type,
                    },
                })
            }
            :None => rewritten.push(method) Option,
        }
    }
    rewritten
}

Option[Type] firstNamedArg(Type ty){
    match ty {
        :Named(value) => { Type
            if value.args.len() > 0 {
                return Option::Some(value.args[0])
            }
            :None Option
        }
        _ => Option::None,
    }
}

bool IsNamedTypeVar(Type ty, String name){
    match ty {
        :Named(value) => value.name == name && value.args.len() == 0 Type,
        _ => false,
    }
}

Type UnwrapRefs(Type ty){
    var current = ty
    while true {
        match current {
            :Reference(value) => current = value.inner.value Type,
            _ => return current,
        }
    }
    current
}

Option[String] baseName(Type ty){
    match UnwrapRefs(ty) {
        :Named(value) => Option::Some(value.name) Type,
        _ => Option::None,
    }
}

Type namedType(String name){
    :Named(NamedType { Type
        name name,
        Vec[Type]() args,
    })
}

BuiltinMethodDecl makeMethod(String name, Option[String] trait_name, String receiver_mode, Vec[Type] params, Type return_type){
    BuiltinMethodDecl {
        name name,
        trait_name trait_name,
        receiver_mode receiver_mode,
        receiverPolicyFor(receiver_mode) receiver_policy,
        FunctionType { signature
            params params,
            Option::Some(return_type) return_type,
        },
    }
}

String receiverPolicyFor(String receiver_mode){
    if receiver_mode == "mut" {
        return "addressable"
    }
    "shared_or_addressable"
}
