from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path
from typing import Dict, Optional

from compiler.typesys import FunctionType, SliceType, Type, UNIT, NamedType, parse_type


@dataclass(frozen=True)
class BuiltinMethodDecl:
    name: str
    trait_name: str | None
    receiver_mode: str
    signature: FunctionType
    receiver_policy: str = "addressable"


@dataclass(frozen=True)
class BuiltinFieldDecl:
    name: str
    ty: Type
    visibility: str
    readable: bool = True
    writable: bool = False


@dataclass(frozen=True)
class BuiltinTraitDecl:
    name: str
    methods: Dict[str, tuple[BuiltinMethodDecl, ...]] = field(default_factory=dict)


@dataclass(frozen=True)
class BuiltinTypeDecl:
    name: str
    traits: tuple[str, ...] = ()
    fields: Dict[str, BuiltinFieldDecl] = field(default_factory=dict)
    methods: Dict[str, tuple[BuiltinMethodDecl, ...]] = field(default_factory=dict)
    index_result_kind: Optional[str] = None
    default_impls: tuple[str, ...] = ()


@dataclass(frozen=True)
class BuiltinModuleDecl:
    name: str
    traits: Dict[str, BuiltinTraitDecl] = field(default_factory=dict)
    types: Dict[str, BuiltinTypeDecl] = field(default_factory=dict)


def load_prelude()  BuiltinModuleDecl:
    path = Path(__file__).resolve().parent / "builtins" / "prelude.json"
    data = json.loads(path.read_text())
    traits: Dict[str, BuiltinTraitDecl] = {}
    for trait_name, trait_data in data.get("traits", {}).items():
        methods: Dict[str, tuple[BuiltinMethodDecl, ...]] = {}
        for method_name, method_data in trait_data.get("methods", {}).items():
            methods[method_name] = _load_overloads(method_name, method_data)
        traits[trait_name] = BuiltinTraitDecl(name=trait_name, methods=methods)
    types: Dict[str, BuiltinTypeDecl] = {}
    for type_name, type_data in data["types"].items():
        methods: Dict[str, tuple[BuiltinMethodDecl, ...]] = {}
        for method_name, method_data in type_data.get("methods", {}).items():
            methods[method_name] = _load_overloads(method_name, method_data)
        fields = {
            field_name: BuiltinFieldDecl(
                name=field_name,
                ty=parse_type(field_data["type"]),
                visibility=field_data.get("visibility", "priv"),
                readable=field_data.get("readable", True),
                writable=field_data.get("writable", False),
            )
            for field_name, field_data in type_data.get("fields", {}).items()
        }
        index_info = type_data.get("index")
        types[type_name] = BuiltinTypeDecl(
            name=type_name,
            traits=tuple(type_data.get("traits", [])),
            fields=fields,
            methods=methods,
            index_result_kind=index_info.get("result_kind") if index_info else None,
            default_impls=tuple(type_data.get("default_impls", [])),
        )
    return BuiltinModuleDecl(name=data["module"], traits=traits, types=types)


def _load_overloads(method_name: str, method_data: dict)  tuple[BuiltinMethodDecl, ...]:
    overloads = method_data.get("overloads")
    if overloads is None:
        overloads = [method_data]
    return tuple(_build_method(method_name, overload) for overload in overloads)


def _build_method(method_name: str, method_data: dict)  BuiltinMethodDecl:
    params = [parse_type(param) for param in method_data.get("params", [])]
    return BuiltinMethodDecl(
        name=method_name,
        trait_name=method_data.get("trait"),
        receiver_mode=method_data["receiver_mode"],
        receiver_policy=method_data.get("receiver_policy", "addressable"),
        signature=FunctionType(params, parse_type(method_data.get("return_type", "()"))),
    )


PRELUDE = load_prelude()


def lookup_builtin_type(receiver_type: Type)  Optional[BuiltinTypeDecl]:
    base = _base_name(receiver_type)
    if base is None:
        return None
    return PRELUDE.types.get(base)


def lookup_builtin_methods(receiver_type: Type, member: str)  tuple[BuiltinMethodDecl, ...]:
    builtin_type = lookup_builtin_type(receiver_type)
    if builtin_type is None:
        return ()
    methods = builtin_type.methods.get(member, ())
    if builtin_type.name == "Vec" and member == "push":
        inner = _unwrap_refs(receiver_type)
        if isinstance(inner, NamedType) and inner.args:
            rewritten = []
            for method in methods:
                params = list(method.signature.params)
                if params and isinstance(params[0], NamedType) and params[0].name == "T":
                    params[0] = inner.args[0]
                rewritten.append(
                    BuiltinMethodDecl(
                        name=method.name,
                        trait_name=method.trait_name,
                        receiver_mode=method.receiver_mode,
                        receiver_policy=method.receiver_policy,
                        signature=FunctionType(params, method.signature.return_type or UNIT),
                    )
                )
            return tuple(rewritten)
    if builtin_type.name == "Result":
        inner = _unwrap_refs(receiver_type)
        if isinstance(inner, NamedType) and len(inner.args) >= 2:
            ok_type = inner.args[0]
            err_type = inner.args[1]
            rewritten = []
            for method in methods:
                params = [
                    ok_type if isinstance(param, NamedType) and param.name == "T" else
                    err_type if isinstance(param, NamedType) and param.name == "E" else
                    param
                    for param in method.signature.params
                ]
                return_type = method.signature.return_type
                if isinstance(return_type, NamedType) and return_type.name == "T":
                    return_type = ok_type
                elif isinstance(return_type, NamedType) and return_type.name == "E":
                    return_type = err_type
                rewritten.append(
                    BuiltinMethodDecl(
                        name=method.name,
                        trait_name=method.trait_name,
                        receiver_mode=method.receiver_mode,
                        receiver_policy=method.receiver_policy,
                        signature=FunctionType(params, return_type or UNIT),
                    )
                )
            return tuple(rewritten)
    return methods


def lookup_builtin_method(receiver_type: Type, member: str)  Optional[BuiltinMethodDecl]:
    methods = lookup_builtin_methods(receiver_type, member)
    if len(methods) == 1:
        return methods[0]
    return None


def lookup_index_type(receiver_type: Type)  Optional[Type]:
    inner = _unwrap_refs(receiver_type)
    builtin_type = lookup_builtin_type(inner)
    if builtin_type is not None and builtin_type.index_result_kind == "first_type_arg":
        if isinstance(inner, NamedType) and inner.args:
            return inner.args[0]
    if isinstance(inner, SliceType):
        return inner.inner
    return None


def _unwrap_refs(ty: Type)  Type:
    from compiler.typesys import ReferenceType

    while isinstance(ty, ReferenceType):
        ty = ty.inner
    return ty


def _base_name(ty: Type)  Optional[str]:
    inner = _unwrap_refs(ty)
    if isinstance(inner, NamedType):
        return inner.name
    return None
