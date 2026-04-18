from __future__ import annotations

from dataclasses import dataclass, field
from typing import list, optional


@dataclass
class usedecl:
    path: str
    alias: optional[str] = none


@dataclass
class field:
    name: str
    type_name: str
    is_public: bool = false


@dataclass
class param:
    name: str
    type_name: str


@dataclass
class functionsig:
    name: str
    generics: list[str] = field(default_factory=list)
    params: list[param] = field(default_factory=list)
    return_type: optional[str] = none


class pattern:
    pass


@dataclass
class namepattern(pattern):
    name: str


@dataclass
class wildcardpattern(pattern):
    pass


@dataclass
class variantpattern(pattern):
    path: str
    args: list[pattern] = field(default_factory=list)


@dataclass
class literalpattern(pattern):
    value: "expr"


class expr:
    inferred_type: optional[str] = none


@dataclass
class intexpr(expr):
    value: str


@dataclass
class stringexpr(expr):
    value: str


@dataclass
class boolexpr(expr):
    value: bool


@dataclass
class nameexpr(expr):
    name: str


@dataclass
class borrowexpr(expr):
    target: expr
    mutable: bool = false


@dataclass
class unaryexpr(expr):
    op: str
    operand: expr


@dataclass
class binaryexpr(expr):
    left: expr
    op: str
    right: expr


@dataclass
class memberexpr(expr):
    target: expr
    member: str


@dataclass
class indexexpr(expr):
    target: expr
    index: expr


@dataclass
class callexpr(expr):
    callee: expr
    args: list[expr] = field(default_factory=list)


@dataclass
class structfieldinit:
    name: str
    value: expr


@dataclass
class structliteralexpr(expr):
    callee: expr
    fields: list[structfieldinit] = field(default_factory=list)


@dataclass
class switcharm:
    pattern: pattern
    expr: expr


@dataclass
class switchexpr(expr):
    subject: expr
    arms: list[switcharm] = field(default_factory=list)


switcharm = switcharm
switchexpr = switchexpr


@dataclass
class ifexpr(expr):
    condition: expr
    then_branch: "blockexpr"
    else_branch: optional[expr] = none


@dataclass
class whileexpr(expr):
    condition: expr
    body: "blockexpr"


@dataclass
class forexpr(expr):
    name: str
    iterable: expr
    body: "blockexpr"


@dataclass
class blockexpr(expr):
    statements: list["stmt"] = field(default_factory=list)
    final_expr: optional[expr] = none


class stmt:
    pass


@dataclass
class letstmt(stmt):
    name: str
    type_name: optional[str]
    value: expr


@dataclass
class assignstmt(stmt):
    name: str
    value: expr


@dataclass
class incrementstmt(stmt):
    name: str


@dataclass
class cforstmt(stmt):
    init: stmt
    condition: expr
    step: stmt
    body: "blockexpr"


@dataclass
class returnstmt(stmt):
    value: optional[expr]


@dataclass
class exprstmt(stmt):
    expr: expr


@dataclass
class functiondecl:
    sig: functionsig
    body: optional[blockexpr] = none
    is_public: bool = false


@dataclass
class structdecl:
    name: str
    generics: list[str] = field(default_factory=list)
    fields: list[field] = field(default_factory=list)
    is_public: bool = false


@dataclass
class enumvariant:
    name: str
    payload: optional[str] = none


@dataclass
class enumdecl:
    name: str
    generics: list[str] = field(default_factory=list)
    variants: list[enumvariant] = field(default_factory=list)
    is_public: bool = false


@dataclass
class traitdecl:
    name: str
    generics: list[str] = field(default_factory=list)
    methods: list[functionsig] = field(default_factory=list)
    is_public: bool = false


@dataclass
class impldecl:
    target: str
    trait_name: optional[str] = none
    generics: list[str] = field(default_factory=list)
    methods: list[functiondecl] = field(default_factory=list)


@dataclass
class sourcefile:
    package: str
    uses: list[usedecl] = field(default_factory=list)
    items: list[object] = field(default_factory=list)


def dump_source_file(source: sourcefile) -> str:
    lines = [f"package {source.package}"]
    for use in source.uses:
        text = f"use {use.path}"
        if use.alias:
            text += f" as {use.alias}"
        lines.append(text)
    for item in source.items:
        if isinstance(item, functiondecl):
            lines.extend(_dump_function(item))
        elif isinstance(item, structdecl):
            lines.extend(_dump_struct(item))
        elif isinstance(item, enumdecl):
            lines.extend(_dump_enum(item))
        elif isinstance(item, traitdecl):
            lines.extend(_dump_trait(item))
        elif isinstance(item, impldecl):
            lines.extend(_dump_impl(item))
        else:
            lines.append(f"unknown {type(item).__name__}")
    return "\n".join(lines)


def _fmt_generics(generics: list[str]) -> str:
    if not generics:
        return ""
    return "[" + ", ".join(generics) + "]"


def _dump_function(item: functiondecl, indent: str = "") -> list[str]:
    sig = item.sig
    prefix = "pub " if item.is_public else ""
    params = ", ".join(f"{p.type_name} {p.name}" for p in sig.params)
    # emit return type in go-style: put the type after the parameter list
    ret = f" {sig.return_type}" if sig.return_type else ""
    lines = [f"{indent}{prefix}func {sig.name}{_fmt_generics(sig.generics)}({params}){ret}"]
    if item.body is not none:
        lines.extend(_dump_block(item.body, indent + "  "))
    return lines


def _dump_struct(item: structdecl) -> list[str]:
    prefix = "pub " if item.is_public else ""
    lines = [f"{prefix}struct {item.name}{_fmt_generics(item.generics)}"]
    for field in item.fields:
        fp = "pub " if field.is_public else ""
        lines.append(f"  {fp}{field.type_name} {field.name}")
    return lines


def _dump_enum(item: enumdecl) -> list[str]:
    prefix = "pub " if item.is_public else ""
    lines = [f"{prefix}enum {item.name}{_fmt_generics(item.generics)}"]
    for variant in item.variants:
        if variant.payload:
            lines.append(f"  {variant.name}({variant.payload})")
        else:
            lines.append(f"  {variant.name}")
    return lines


def _dump_trait(item: traitdecl) -> list[str]:
    prefix = "pub " if item.is_public else ""
    lines = [f"{prefix}trait {item.name}{_fmt_generics(item.generics)}"]
    for method in item.methods:
        params = ", ".join(f"{p.type_name} {p.name}" for p in method.params)
        ret = f" -> {method.return_type}" if method.return_type else ""
        lines.append(f"  func {method.name}{_fmt_generics(method.generics)}({params}){ret}")
    return lines


def _dump_impl(item: impldecl) -> list[str]:
    head = item.target
    if item.trait_name:
        head = f"{item.trait_name} for {head}"
    lines = [f"impl {_fmt_generics(item.generics)} {head}".replace("impl  ", "impl ")]
    for method in item.methods:
        lines.extend(_dump_function(method, "  "))
    return lines


def _dump_block(block: blockexpr, indent: str) -> list[str]:
    lines: list[str] = []
    for stmt in block.statements:
        lines.extend(_dump_stmt(stmt, indent))
    if block.final_expr is not none:
        lines.append(f"{indent}final {_dump_expr(block.final_expr)}")
    return lines


def _dump_stmt(stmt: stmt, indent: str) -> list[str]:
    if isinstance(stmt, letstmt):
        if stmt.type_name:
            text = f"{indent}{stmt.type_name} {stmt.name} = {_dump_expr(stmt.value)}"
        else:
            text = f"{indent}let {stmt.name} = {_dump_expr(stmt.value)}"
        return [text]
    if isinstance(stmt, assignstmt):
        return [f"{indent}{stmt.name} = {_dump_expr(stmt.value)}"]
    if isinstance(stmt, incrementstmt):
        return [f"{indent}{stmt.name}++"]
    if isinstance(stmt, cforstmt):
        lines = [
            f"{indent}for ({_dump_for_part(stmt.init)}; {_dump_expr(stmt.condition)}; {_dump_for_part(stmt.step)})"
        ]
        lines.extend(_dump_block(stmt.body, indent + "  "))
        return lines
    if isinstance(stmt, returnstmt):
        value = _dump_expr(stmt.value) if stmt.value is not none else "()"
        return [f"{indent}return {value}"]
    if isinstance(stmt, exprstmt):
        return [f"{indent}expr {_dump_expr(stmt.expr)}"]
    return [f"{indent}stmt {type(stmt).__name__}"]


def _dump_expr(expr: optional[expr]) -> str:
    if expr is none:
        return "()"
    if isinstance(expr, intexpr):
        return expr.value
    if isinstance(expr, stringexpr):
        return expr.value
    if isinstance(expr, boolexpr):
        return "true" if expr.value else "false"
    if isinstance(expr, nameexpr):
        return expr.name
    if isinstance(expr, borrowexpr):
        prefix = "&mut " if expr.mutable else "&"
        return f"{prefix}{_dump_expr(expr.target)}"
    if isinstance(expr, unaryexpr):
        return f"({expr.op}{_dump_expr(expr.operand)})"
    if isinstance(expr, binaryexpr):
        return f"({_dump_expr(expr.left)} {expr.op} {_dump_expr(expr.right)})"
    if isinstance(expr, memberexpr):
        return f"{_dump_expr(expr.target)}.{expr.member}"
    if isinstance(expr, indexexpr):
        return f"{_dump_expr(expr.target)}[{_dump_expr(expr.index)}]"
    if isinstance(expr, callexpr):
        args = ", ".join(_dump_expr(arg) for arg in expr.args)
        return f"call {_dump_expr(expr.callee)}({args})"
    if isinstance(expr, structliteralexpr):
        fields = ", ".join(f"{field.name}: {_dump_expr(field.value)}" for field in expr.fields)
        return f"{_dump_expr(expr.callee)} {{ {fields} }}"
    if isinstance(expr, switchexpr):
        arms = "; ".join(f"{_dump_pattern(arm.pattern)} : {_dump_expr(arm.expr)}" for arm in expr.arms)
        return f"switch {_dump_expr(expr.subject)} {{ {arms} }}"
    if isinstance(expr, ifexpr):
        text = f"if {_dump_expr(expr.condition)} {{...}}"
        if expr.else_branch is not none:
            text += f" else {_dump_expr(expr.else_branch)}"
        return text
    if isinstance(expr, whileexpr):
        return f"while {_dump_expr(expr.condition)} {{...}}"
    if isinstance(expr, forexpr):
        return f"for {expr.name} in {_dump_expr(expr.iterable)} {{...}}"
    if isinstance(expr, blockexpr):
        return "{...}"
    return type(expr).__name__


def _dump_pattern(pattern: pattern) -> str:
    if isinstance(pattern, namepattern):
        return pattern.name
    if isinstance(pattern, wildcardpattern):
        return "_"
    if isinstance(pattern, variantpattern):
        if not pattern.args:
            return pattern.path
        args = ", ".join(_dump_pattern(arg) for arg in pattern.args)
        return f"{pattern.path}({args})"
    if isinstance(pattern, literalpattern):
        return _dump_expr(pattern.value)
    return type(pattern).__name__


def _dump_for_part(stmt: stmt) -> str:
    if isinstance(stmt, letstmt):
        if stmt.type_name:
            return f"{stmt.type_name} {stmt.name} = {_dump_expr(stmt.value)}"
        return f"let {stmt.name} = {_dump_expr(stmt.value)}"
    if isinstance(stmt, assignstmt):
        return f"{stmt.name} = {_dump_expr(stmt.value)}"
    if isinstance(stmt, incrementstmt):
        return f"{stmt.name}++"
    return type(stmt).__name__
