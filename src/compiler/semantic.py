from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from compiler.ast import (
    AssignStmt,
    BinaryExpr,
    BlockExpr,
    BoolExpr,
    BorrowExpr,
    CallExpr,
    CForStmt,
    EnumDecl,
    Expr,
    ExprStmt,
    ForExpr,
    FunctionDecl,
    IfExpr,
    ImplDecl,
    IncrementStmt,
    IndexExpr,
    IntExpr,
    LetStmt,
    MatchExpr,
    MemberExpr,
    NameExpr,
    NamePattern,
    Param,
    Pattern,
    ReturnStmt,
    SourceFile,
    StringExpr,
    StructDecl,
    TraitDecl,
    UseDecl,
    VariantPattern,
    WhileExpr,
    WildcardPattern,
)
from compiler.borrow import analyze_block
from compiler.ownership import make_plan
from compiler.prelude import BuiltinMethodDecl, lookup_builtin_methods, lookup_builtin_type, lookup_index_type
from compiler.typesys import (
    BOOL,
    FunctionType,
    I32,
    NEVER,
    STRING,
    UNIT,
    NamedType,
    ReferenceType,
    SliceType,
    Type,
    UnknownType,
    dump_type,
    is_copy_type,
    parse_type,
    substitute_type,
)


@dataclass
class Diagnostic:
    message: str


@dataclass
class FunctionInfo:
    generics: List[str]
    params: List[Type]
    return_type: Type


@dataclass
class EnumInfo:
    generics: List[str]
    variants: Dict[str, Optional[Type]]


@dataclass
class StructInfo:
    fields: Dict[str, Type]


@dataclass
class TraitMethodInfo:
    owner: str
    generics: List[str]
    params: List[Type]
    return_type: Type
    has_receiver: bool = False
    receiver_mode: str = "value"


@dataclass
class ImplInfo:
    trait_name: Optional[str]
    target: str
    methods: Dict[str, TraitMethodInfo]


@dataclass
class CheckResult:
    diagnostics: List[Diagnostic] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.diagnostics


@dataclass
class VarState:
    ty: Type
    moved: bool = False
    shared_borrows: int = 0
    mut_borrowed: bool = False


def check_source(source: SourceFile) -> CheckResult:
    checker = Checker()
    checker.load_items(source)
    checker.check(source)
    return CheckResult(diagnostics=checker.diagnostics)


class Checker:
    def __init__(self) -> None:
        self.diagnostics: List[Diagnostic] = []
        self.functions: Dict[str, FunctionInfo] = {}
        self.enums: Dict[str, EnumInfo] = {}
        self.structs: Dict[str, StructInfo] = {}
        self.variant_to_enum: Dict[str, str] = {}
        self.imported_functions: Dict[str, TraitMethodInfo] = {}
        self.type_aliases: Dict[str, str] = {}
        self.traits: set[str] = {"Copy", "Clone", "Eq", "Ord"}
        self.impl_traits: Dict[str, set[str]] = {}
        self.trait_methods: Dict[str, Dict[str, TraitMethodInfo]] = {}
        self.impls: List[ImplInfo] = []
        self._current_type_env: Dict[str, Type] = {}
        self._current_return_type: Type = UNIT
        self.builtin_functions: Dict[str, TraitMethodInfo] = {
            "println": TraitMethodInfo(
                owner="builtin",
                generics=["T"],
                params=[NamedType("T")],
                return_type=UNIT,
            ),
            "eprintln": TraitMethodInfo(
                owner="builtin",
                generics=["T"],
                params=[NamedType("T")],
                return_type=UNIT,
            ),
            "__host_run_shell": TraitMethodInfo(
                owner="builtin",
                generics=[],
                params=[STRING],
                return_type=I32,
            ),
            "__host_run_process1": TraitMethodInfo(
                owner="builtin",
                generics=[],
                params=[STRING],
                return_type=I32,
            ),
            "__host_run_process5": TraitMethodInfo(
                owner="builtin",
                generics=[],
                params=[STRING, STRING, STRING, STRING, STRING],
                return_type=I32,
            ),
            "__host_run_process_argv": TraitMethodInfo(
                owner="builtin",
                generics=[],
                params=[STRING],
                return_type=I32,
            ),
        }
        self._load_stdlib_primitives()

    def load_items(self, source: SourceFile) -> None:
        self._load_use_decls(source.uses)
        for item in source.items:
            if isinstance(item, FunctionDecl):
                self.functions[item.sig.name] = FunctionInfo(
                    generics=item.sig.generics,
                    params=[self._normalize_type(parse_type(param.type_name)) for param in item.sig.params],
                    return_type=self._normalize_type(parse_type(item.sig.return_type or "()")),
                )
            elif isinstance(item, EnumDecl):
                info = EnumInfo(
                    generics=item.generics,
                    variants={
                        variant.name: self._normalize_type(parse_type(variant.payload)) if variant.payload else None
                        for variant in item.variants
                    },
                )
                self.enums[item.name] = info
                for variant in item.variants:
                    self.variant_to_enum[variant.name] = item.name
            elif isinstance(item, StructDecl):
                self.structs[item.name] = StructInfo(
                    fields={field.name: self._normalize_type(parse_type(field.type_name)) for field in item.fields}
                )
            elif isinstance(item, TraitDecl):
                self.traits.add(item.name)
                self.trait_methods[item.name] = {
                    method.name: TraitMethodInfo(
                        owner=item.name,
                        generics=method.generics,
                        params=[self._normalize_type(parse_type(param.type_name)) for param in method.params],
                        return_type=self._normalize_type(parse_type(method.return_type or "()")),
                        has_receiver=bool(method.params and method.params[0].name == "self"),
                        receiver_mode=self._receiver_mode(method.params[0] if method.params else None),
                    )
                    for method in item.methods
                }
            elif isinstance(item, ImplDecl):
                methods = {
                    method.sig.name: TraitMethodInfo(
                        owner=item.target,
                        generics=method.sig.generics,
                        params=[self._normalize_type(parse_type(param.type_name)) for param in method.sig.params],
                        return_type=self._normalize_type(parse_type(method.sig.return_type or "()")),
                        has_receiver=bool(method.sig.params and method.sig.params[0].name == "self"),
                        receiver_mode=self._receiver_mode(method.sig.params[0] if method.sig.params else None),
                    )
                    for method in item.methods
                }
                self.impls.append(ImplInfo(trait_name=item.trait_name, target=item.target, methods=methods))
                if item.trait_name:
                    self.traits.add(item.trait_name)
                    self.impl_traits.setdefault(item.target, set()).add(item.trait_name)

    def check(self, source: SourceFile) -> None:
        for item in source.items:
            if isinstance(item, FunctionDecl) and item.body is not None:
                self._check_function(item)

    def _check_function(self, item: FunctionDecl) -> None:
        scope: Dict[str, VarState] = {}
        self._current_type_env = {}
        previous_return = self._current_return_type
        self._current_return_type = self._normalize_type(parse_type(item.sig.return_type or "()"))
        for param in item.sig.params:
            ty = self._normalize_type(parse_type(param.type_name))
            scope[param.name] = VarState(ty)
            self._current_type_env[param.name] = ty
        initial_scope = self._clone_scope(scope)
        self._check_block(item.body, scope, self._current_return_type)
        cfg_diags = analyze_block(item.body, initial_scope, make_plan(self._current_type_env))
        for diag in cfg_diags:
            self._error(diag.message)
        self._current_return_type = previous_return

    def _check_block(self, block: BlockExpr, scope: Dict[str, VarState], expected_return: Type) -> Type:
        local_scope = self._clone_scope(scope)
        terminated = False
        for stmt in block.statements:
            if self._check_stmt(stmt, local_scope, expected_return):
                terminated = True
                break
        final_type = NEVER if terminated and block.final_expr is None else (
            self._infer_expr_with_hint(block.final_expr, local_scope, expected_return) if block.final_expr is not None else UNIT
        )
        if block.final_expr is not None:
            self._consume_tail_expr(block.final_expr, local_scope)
        if not self._type_eq(expected_return, UNIT) and block.final_expr is not None and not self._type_eq(expected_return, final_type):
            self._error(f"block expected {dump_type(expected_return)}, got {dump_type(final_type)}")
        self._merge_back(scope, local_scope)
        return final_type

    def _check_stmt(self, stmt, scope: Dict[str, VarState], expected_return: Type) -> bool:
        if isinstance(stmt, LetStmt):
            value_type = self._infer_expr(stmt.value, scope)
            declared = self._normalize_type(parse_type(stmt.type_name)) if stmt.type_name else None
            if declared and not self._type_eq(declared, value_type):
                self._error(f"let {stmt.name} expected {dump_type(declared)}, got {dump_type(value_type)}")
            resolved = declared or value_type
            scope[stmt.name] = VarState(resolved)
            self._current_type_env[stmt.name] = resolved
            return False
        if isinstance(stmt, AssignStmt):
            state = scope.get(stmt.name)
            if state is None:
                self._error(f"unresolved name {stmt.name}")
                self._infer_expr(stmt.value, scope)
                return False
            value_type = self._infer_expr(stmt.value, scope)
            if not self._type_eq(state.ty, value_type):
                self._error(f"assign {stmt.name} expected {dump_type(state.ty)}, got {dump_type(value_type)}")
            return False
        if isinstance(stmt, IncrementStmt):
            state = scope.get(stmt.name)
            if state is None:
                self._error(f"unresolved name {stmt.name}")
                return False
            if not self._type_eq(state.ty, I32):
                self._error(f"increment {stmt.name} expected i32, got {dump_type(state.ty)}")
            return False
        if isinstance(stmt, CForStmt):
            loop_scope = self._clone_scope(scope)
            self._check_stmt(stmt.init, loop_scope, expected_return)
            cond_type = self._infer_expr(stmt.condition, loop_scope)
            if not self._type_eq(cond_type, BOOL):
                self._error(f"for condition expected bool, got {dump_type(cond_type)}")
            body_scope = self._clone_scope(loop_scope)
            self._check_block(stmt.body, body_scope, UNIT)
            self._check_stmt(stmt.step, body_scope, expected_return)
            self._merge_back(scope, body_scope)
            return False
        if isinstance(stmt, ReturnStmt):
            actual = self._infer_expr_with_hint(stmt.value, scope, self._current_return_type) if stmt.value is not None else UNIT
            if not self._type_eq(self._current_return_type, actual):
                self._error(f"return expected {dump_type(self._current_return_type)}, got {dump_type(actual)}")
            return True
        if isinstance(stmt, ExprStmt):
            return self._is_never(self._infer_expr(stmt.expr, scope))
        return False

    def _infer_expr(self, expr: Optional[Expr], scope: Dict[str, VarState]) -> Type:
        return self._infer_expr_with_hint(expr, scope, None)

    def _infer_expr_with_hint(self, expr: Optional[Expr], scope: Dict[str, VarState], expected_type: Optional[Type]) -> Type:
        if expr is None:
            return UNIT
        if isinstance(expr, IntExpr):
            expr.inferred_type = dump_type(I32)
            return I32
        if isinstance(expr, StringExpr):
            expr.inferred_type = dump_type(STRING)
            return STRING
        if isinstance(expr, BoolExpr):
            expr.inferred_type = dump_type(BOOL)
            return BOOL
        if isinstance(expr, NameExpr):
            state = scope.get(expr.name)
            if state is None:
                if expr.name in self.variant_to_enum:
                    ty = self._infer_unit_variant_name(expr.name, expected_type)
                    expr.inferred_type = dump_type(ty)
                    return ty
                imported = self.imported_functions.get(expr.name)
                if imported is not None:
                    ty = FunctionType(imported.params, imported.return_type)
                    expr.inferred_type = dump_type(ty)
                    return ty
                self._error(f"unresolved name {expr.name}")
                return UnknownType()
            if state.moved:
                self._error(f"use of moved value {expr.name}")
            expr.inferred_type = dump_type(state.ty)
            return state.ty
        if isinstance(expr, BorrowExpr):
            if isinstance(expr.target, NameExpr):
                state = scope.get(expr.target.name)
                if state is None:
                    self._error(f"unresolved name {expr.target.name}")
                    return UnknownType()
                if state.moved:
                    self._error(f"borrow of moved value {expr.target.name}")
                if expr.mutable:
                    if state.shared_borrows > 0 or state.mut_borrowed:
                        self._error(f"cannot mutably borrow {expr.target.name} while borrowed")
                    state.mut_borrowed = True
                else:
                    if state.mut_borrowed:
                        self._error(f"cannot immutably borrow {expr.target.name} while mutably borrowed")
                    state.shared_borrows += 1
                ty = ReferenceType(state.ty, mutable=expr.mutable)
                expr.inferred_type = dump_type(ty)
                return ty
            self._error("borrow target must be a name in MVP")
            return UnknownType()
        if isinstance(expr, BinaryExpr):
            left = self._infer_expr(expr.left, scope)
            right = self._infer_expr(expr.right, scope)
            result = self._infer_binary(expr.op, left, right)
            expr.inferred_type = dump_type(result)
            return result
        if isinstance(expr, MemberExpr):
            target = self._inspect_expr_type(expr.target, scope)
            member_type = self._resolve_member(target, expr.member)
            if member_type is None:
                self._error(f"unknown member {expr.member} on {dump_type(target)}")
                return UnknownType()
            expr.inferred_type = dump_type(member_type)
            return member_type
        if isinstance(expr, IndexExpr):
            target = self._inspect_expr_type(expr.target, scope)
            index = self._infer_expr(expr.index, scope)
            if not self._type_eq(index, I32):
                self._error(f"index expected i32, got {dump_type(index)}")
            result = self._resolve_index(target)
            expr.inferred_type = dump_type(result)
            return result
        if isinstance(expr, CallExpr):
            variant_result = self._infer_variant_constructor_call(expr, scope, expected_type)
            if variant_result is not None:
                expr.inferred_type = dump_type(variant_result)
                return variant_result
            constructed = self._infer_type_constructor_call(expr.callee, expr.args)
            if constructed is not None:
                expr.inferred_type = dump_type(constructed)
                return constructed
            if isinstance(expr.callee, MemberExpr):
                method_info = self._resolve_method_call(expr.callee, expr.args, scope)
                if method_info is not None:
                    return self._check_callable(method_info, expr.args, scope, expr.callee.member, expr)
            if isinstance(expr.callee, NameExpr) and expr.callee.name in self.functions:
                info = self.functions[expr.callee.name]
                method_like = TraitMethodInfo(
                    owner=expr.callee.name,
                    generics=info.generics,
                    params=info.params,
                    return_type=info.return_type,
                )
                return self._check_callable(method_like, expr.args, scope, expr.callee.name, expr)
            if isinstance(expr.callee, NameExpr) and expr.callee.name in self.builtin_functions:
                return self._check_callable(
                    self.builtin_functions[expr.callee.name],
                    expr.args,
                    scope,
                    expr.callee.name,
                    expr,
                )
            if isinstance(expr.callee, NameExpr) and expr.callee.name in self.imported_functions:
                return self._check_callable(
                    self.imported_functions[expr.callee.name],
                    expr.args,
                    scope,
                    expr.callee.name,
                    expr,
                )
            self._infer_expr(expr.callee, scope)
            for arg in expr.args:
                self._infer_expr(arg, scope)
            return UnknownType()
        if isinstance(expr, BlockExpr):
            ty = self._check_block(expr, scope, UNIT)
            expr.inferred_type = dump_type(ty)
            return ty
        if isinstance(expr, IfExpr):
            cond = self._infer_expr(expr.condition, scope)
            if not self._type_eq(cond, BOOL):
                self._error(f"if condition expected bool, got {dump_type(cond)}")
            then_scope = self._clone_scope(scope)
            then_type = self._check_block(expr.then_branch, then_scope, expected_type or UNIT)
            else_type = UNIT
            else_scope = self._clone_scope(scope)
            if expr.else_branch is not None:
                else_type = self._infer_expr_with_hint(expr.else_branch, else_scope, expected_type)
            self._join_scopes(scope, then_scope, else_scope)
            if expr.else_branch is None:
                expr.inferred_type = dump_type(UNIT)
                return UNIT
            if self._is_never(then_type):
                expr.inferred_type = dump_type(else_type)
                return else_type
            if self._is_never(else_type):
                expr.inferred_type = dump_type(then_type)
                return then_type
            if not self._type_eq(then_type, else_type):
                self._error(f"if branch type mismatch: {dump_type(then_type)} vs {dump_type(else_type)}")
                return UnknownType()
            expr.inferred_type = dump_type(then_type)
            return then_type
        if isinstance(expr, WhileExpr):
            cond = self._infer_expr(expr.condition, scope)
            if not self._type_eq(cond, BOOL):
                self._error(f"while condition expected bool, got {dump_type(cond)}")
            body_scope = self._clone_scope(scope)
            self._check_block(expr.body, body_scope, UNIT)
            self._join_scopes(scope, body_scope, scope)
            expr.inferred_type = dump_type(UNIT)
            return UNIT
        if isinstance(expr, ForExpr):
            iter_type = self._infer_expr(expr.iterable, scope)
            body_scope = self._clone_scope(scope)
            item_type = self._infer_iter_item(iter_type)
            body_scope[expr.name] = VarState(item_type)
            self._current_type_env.setdefault(expr.name, item_type)
            self._check_block(expr.body, body_scope, UNIT)
            self._join_scopes(scope, body_scope, scope)
            expr.inferred_type = dump_type(UNIT)
            return UNIT
        if isinstance(expr, MatchExpr):
            subject_type = self._infer_expr(expr.subject, scope)
            arm_type: Optional[Type] = None
            arm_scopes = []
            for arm in expr.arms:
                arm_scope = self._clone_scope(scope)
                self._bind_pattern(arm.pattern, subject_type, arm_scope)
                current = self._infer_expr_with_hint(arm.expr, arm_scope, expected_type)
                arm_scopes.append(arm_scope)
                if self._is_never(current):
                    continue
                if arm_type is None or self._is_never(arm_type):
                    arm_type = current
                elif not self._type_eq(arm_type, current):
                    self._error(f"match arm type mismatch: {dump_type(arm_type)} vs {dump_type(current)}")
            if arm_scopes:
                merged = arm_scopes[0]
                for extra in arm_scopes[1:]:
                    self._join_scopes(merged, merged, extra)
                self._merge_back(scope, merged)
            result = arm_type or UnknownType()
            expr.inferred_type = dump_type(result)
            return result
        self._error(f"unhandled expr {type(expr).__name__}")
        return UnknownType()

    def _infer_variant_constructor_call(
        self,
        expr: CallExpr,
        scope: Dict[str, VarState],
        expected_type: Optional[Type],
    ) -> Optional[Type]:
        if not isinstance(expr.callee, NameExpr):
            return None
        variant_name = self._variant_name(expr.callee.name)
        enum_name = self.variant_to_enum.get(variant_name)
        if enum_name is None:
            return None
        expected_type = self._normalize_type(expected_type) if expected_type is not None else None
        if not isinstance(expected_type, NamedType) or expected_type.name != enum_name:
            for arg in expr.args:
                self._infer_expr(arg, scope)
            return UnknownType()
        payload_type = self._resolve_variant_payload_type(variant_name, expected_type)
        if payload_type is None:
            if expr.args:
                self._error(f"variant {variant_name} does not take payload")
            return expected_type
        if len(expr.args) != 1:
            self._error(f"variant {variant_name} expects 1 payload")
            return expected_type
        actual_payload = self._infer_expr(expr.args[0], scope)
        if not self._type_eq(payload_type, actual_payload):
            self._error(f"call {variant_name} expected {dump_type(payload_type)}, got {dump_type(actual_payload)}")
        return expected_type

    def _infer_unit_variant_name(self, name: str, expected_type: Optional[Type]) -> Type:
        variant_name = self._variant_name(name)
        enum_name = self.variant_to_enum.get(variant_name)
        normalized_expected = self._normalize_type(expected_type) if expected_type is not None else None
        if isinstance(normalized_expected, NamedType) and normalized_expected.name == enum_name:
            payload_type = self._resolve_variant_payload_type(variant_name, normalized_expected)
            if payload_type is None:
                return normalized_expected
        return NamedType(name)

    def _infer_type_constructor_call(self, callee: Expr, args: List[Expr]) -> Optional[Type]:
        if args:
            return None
        if isinstance(callee, IndexExpr) and isinstance(callee.target, NameExpr):
            base = self.type_aliases.get(callee.target.name, callee.target.name)
            if base == "Vec":
                element = self._type_from_expr(callee.index)
                if element is not None:
                    return NamedType("Vec", [element])
        if isinstance(callee, NameExpr):
            base = self.type_aliases.get(callee.name, callee.name)
            if base == "Vec":
                return NamedType("Vec")
        return None

    def _is_never(self, ty: Type) -> bool:
        return isinstance(self._normalize_type(ty), type(NEVER))

    def _consume_tail_expr(self, expr: Expr, scope: Dict[str, VarState]) -> None:
        if isinstance(expr, NameExpr):
            state = scope.get(expr.name)
            if state is None:
                return
            if not is_copy_type(state.ty):
                state.moved = True

    def _type_from_expr(self, expr: Expr) -> Optional[Type]:
        if isinstance(expr, NameExpr):
            return self._normalize_type(parse_type(expr.name))
        if isinstance(expr, IndexExpr) and isinstance(expr.target, NameExpr):
            base = self.type_aliases.get(expr.target.name, expr.target.name)
            inner = self._type_from_expr(expr.index)
            if inner is not None:
                return NamedType(base, [inner])
        return None

    def _bind_pattern(self, pattern: Pattern, subject_type: Type, scope: Dict[str, VarState]) -> None:
        if isinstance(pattern, WildcardPattern):
            return
        if isinstance(pattern, NamePattern):
            scope[pattern.name] = VarState(subject_type)
            return
        if isinstance(pattern, VariantPattern):
            variant_name = self._variant_name(pattern.path)
            expected_payload = self._resolve_variant_payload_type(variant_name, subject_type)
            if variant_name not in self.variant_to_enum:
                self._error(f"unknown match variant {pattern.path}")
            if expected_payload is None and pattern.args:
                self._error(f"variant {pattern.path} does not take payload")
            if expected_payload is not None and len(pattern.args) != 1:
                self._error(f"variant {pattern.path} expects 1 payload")
            for arg in pattern.args:
                self._bind_pattern(arg, expected_payload or UnknownType(), scope)

    def _resolve_variant_payload_type(self, variant_name: str, subject_type: Type) -> Optional[Type]:
        subject_type = self._normalize_type(subject_type)
        enum_name = self.variant_to_enum.get(variant_name)
        if enum_name is None:
            return None
        enum_info = self.enums.get(enum_name)
        if enum_info is None:
            return None
        payload = enum_info.variants.get(variant_name)
        if payload is None:
            return None
        if isinstance(subject_type, NamedType) and subject_type.name == enum_name:
            mapping = {name: arg for name, arg in zip(enum_info.generics, subject_type.args)}
            return substitute_type(payload, mapping)
        return payload

    def _infer_binary(self, op: str, left: Type, right: Type) -> Type:
        left = self._normalize_type(left)
        right = self._normalize_type(right)
        if op == "+":
            if self._type_eq(left, I32) and self._type_eq(right, I32):
                return I32
            if self._type_eq(left, STRING) and self._type_eq(right, STRING):
                return STRING
            self._error(f"operator + expects matching i32/String operands, got {dump_type(left)} and {dump_type(right)}")
            return UnknownType()
        if op in {"+", "-", "*", "/", "%"}:
            if self._type_eq(left, I32) and self._type_eq(right, I32):
                return I32
            self._error(f"operator {op} expects i32 operands, got {dump_type(left)} and {dump_type(right)}")
            return UnknownType()
        if op in {"==", "!=", "<", "<=", ">", ">="}:
            if self._type_eq(left, right):
                return BOOL
            self._error(f"operator {op} expects matching operand types, got {dump_type(left)} and {dump_type(right)}")
            return BOOL
        if op in {"&&", "||"}:
            if self._type_eq(left, BOOL) and self._type_eq(right, BOOL):
                return BOOL
            self._error(f"operator {op} expects bool operands, got {dump_type(left)} and {dump_type(right)}")
            return BOOL
        self._error(f"unknown operator {op}")
        return UnknownType()

    def _type_eq(self, left: Type, right: Type) -> bool:
        return dump_type(self._normalize_type(left)) == dump_type(self._normalize_type(right))

    def _unify_types(self, expected: Type, actual: Type, subst: Dict[str, Type]) -> bool:
        if isinstance(expected, NamedType) and not expected.args and expected.name.isupper():
            bound = subst.get(expected.name)
            if bound is None:
                subst[expected.name] = actual
                return True
            return self._type_eq(bound, actual)
        if isinstance(expected, NamedType) and isinstance(actual, NamedType):
            if expected.name != actual.name or len(expected.args) != len(actual.args):
                return False
            return all(self._unify_types(e, a, subst) for e, a in zip(expected.args, actual.args))
        if isinstance(expected, ReferenceType) and isinstance(actual, ReferenceType):
            if expected.mutable != actual.mutable:
                return False
            return self._unify_types(expected.inner, actual.inner, subst)
        return self._type_eq(expected, actual)

    def _check_generic_bounds(self, generic_specs: List[str], subst: Dict[str, Type]) -> bool:
        ok = True
        for spec in generic_specs:
            if ":" not in spec:
                continue
            name, bounds_text = spec.split(":", 1)
            ty = subst.get(name.strip())
            if ty is None:
                continue
            for bound in [part.strip() for part in bounds_text.split("+")]:
                if not self._implements_trait(ty, bound):
                    self._error(f"type {dump_type(ty)} does not satisfy bound {bound}")
                    ok = False
        return ok

    def _implements_trait(self, ty: Type, trait_name: str) -> bool:
        if trait_name == "Copy":
            return is_copy_type(ty)
        if trait_name == "Clone":
            return is_copy_type(ty) or dump_type(ty) in {"String"}
        builtin = lookup_builtin_type(ty)
        if builtin is not None and trait_name in builtin.traits:
            return True
        name = dump_type(ty)
        return trait_name in self.impl_traits.get(name, set())

    def _infer_iter_item(self, ty: Type) -> Type:
        if isinstance(ty, NamedType) and ty.name == "Vec" and ty.args:
            return ty.args[0]
        if isinstance(ty, SliceType):
            return ty.inner
        if isinstance(ty, ReferenceType):
            return ty.inner
        return UnknownType("iter_item")

    def _resolve_index(self, target: Type) -> Type:
        resolved = lookup_index_type(target)
        return resolved or UnknownType("index")

    def _resolve_member(self, target: Type, member: str) -> Optional[Type]:
        if isinstance(target, ReferenceType):
            return self._resolve_member(target.inner, member)
        if isinstance(target, NamedType):
            if target.name == "Option":
                if member == "is_some" or member == "is_none":
                    return BOOL
                if member == "unwrap" and target.args:
                    return target.args[0]
                if member == "unwrap_or" and target.args:
                    return target.args[0]
            struct_info = self.structs.get(target.name)
            if struct_info and member in struct_info.fields:
                return struct_info.fields[member]
            builtin_type = lookup_builtin_type(target)
            if builtin_type is not None and member in builtin_type.fields:
                field = builtin_type.fields[member]
                if not field.readable:
                    self._error(f"field {member} on {dump_type(target)} is not readable")
                    return None
                return field.ty
            method_sig = self._lookup_method(target, member)
            if method_sig is not None:
                return FunctionType(method_sig.params, method_sig.return_type)
            builtins = lookup_builtin_methods(target, member)
            if len(builtins) == 1:
                return builtins[0].signature
            if len(builtins) > 1:
                self._error(f"cannot refer to overloaded builtin method {member} without call")
                return None
        return None

    def _resolve_method_call(
        self,
        callee: MemberExpr,
        args: List[Expr],
        scope: Dict[str, VarState],
    ) -> Optional[TraitMethodInfo]:
        receiver_type = self._inspect_expr_type(callee.target, scope)
        method_sig = self._lookup_method(receiver_type, callee.member)
        if method_sig is None:
            builtin = self._select_builtin_method(receiver_type, callee.member, callee.target, args, scope)
            if builtin is not None:
                return TraitMethodInfo(
                    "builtin",
                    [],
                    builtin.signature.params,
                    builtin.signature.return_type or UNIT,
                    False,
                    builtin.receiver_mode,
                )
            self._error(f"no method {callee.member} for {dump_type(receiver_type)}")
            return None
        self._validate_receiver(method_sig, receiver_type, callee.target, callee.member)
        params = method_sig.params
        if method_sig.has_receiver and params:
            params = params[1:]
        return TraitMethodInfo(
            method_sig.owner,
            method_sig.generics,
            params,
            method_sig.return_type,
            has_receiver=False,
            receiver_mode=method_sig.receiver_mode,
        )

    def _lookup_method(self, receiver_type: Type, method_name: str) -> Optional[TraitMethodInfo]:
        receiver_name = dump_type(receiver_type.inner if isinstance(receiver_type, ReferenceType) else receiver_type)
        candidates: List[TraitMethodInfo] = []
        for impl_info in self.impls:
            if impl_info.target == receiver_name and method_name in impl_info.methods:
                candidates.append(impl_info.methods[method_name])
        if len(candidates) > 1:
            owners = ", ".join(candidate.owner for candidate in candidates)
            self._error(f"multiple method candidates for {receiver_name}.{method_name}: {owners}")
            return candidates[0]
        return candidates[0] if candidates else None

    def _select_builtin_method(
        self,
        receiver_type: Type,
        method_name: str,
        receiver_expr: Expr,
        expr_args: List[Expr],
        scope: Dict[str, VarState],
    ):
        if isinstance(receiver_type, NamedType) and receiver_type.name == "Option":
            option_inner = receiver_type.args[0] if receiver_type.args else UnknownType()
            if method_name == "is_some" or method_name == "is_none":
                return BuiltinMethodDecl(
                    name=method_name,
                    trait_name=None,
                    receiver_mode="ref",
                    receiver_policy="shared_or_addressable",
                    signature=FunctionType([], BOOL),
                )
            if method_name == "unwrap":
                return BuiltinMethodDecl(
                    name=method_name,
                    trait_name=None,
                    receiver_mode="ref",
                    receiver_policy="shared_or_addressable",
                    signature=FunctionType([], option_inner),
                )
            if method_name == "unwrap_or":
                return BuiltinMethodDecl(
                    name=method_name,
                    trait_name=None,
                    receiver_mode="ref",
                    receiver_policy="shared_or_addressable",
                    signature=FunctionType([option_inner], option_inner),
                )
        candidates = list(lookup_builtin_methods(receiver_type, method_name))
        if not candidates:
            return None
        arity_matches = [candidate for candidate in candidates if len(candidate.signature.params) == len(expr_args)]
        if not arity_matches:
            self._error(f"call {method_name} expected one of {[len(c.signature.params) for c in candidates]} args, got {len(expr_args)}")
            return candidates[0]
        viable = []
        for candidate in arity_matches:
            if self._builtin_receiver_ok(candidate, receiver_type, receiver_expr):
                viable.append(candidate)
        if not viable:
            self._validate_builtin_receiver(arity_matches[0], receiver_type, receiver_expr, method_name)
            return arity_matches[0]
        if len(viable) > 1:
            self._error(f"multiple builtin overloads for {dump_type(receiver_type)}.{method_name}")
            return viable[0]
        return viable[0]

    def _check_callable(
        self,
        info: TraitMethodInfo,
        args: List[Expr],
        scope: Dict[str, VarState],
        name: str,
        owner_expr: Expr,
    ) -> Type:
        if len(info.params) != len(args):
            self._error(f"call {name} expected {len(info.params)} args, got {len(args)}")
        subst: Dict[str, Type] = {}
        for arg, param_type in zip(args, info.params):
            arg_type = self._infer_expr(arg, scope)
            if not self._unify_types(param_type, arg_type, subst):
                self._error(f"call {name} expected {dump_type(param_type)}, got {dump_type(arg_type)}")
        if not self._check_generic_bounds(info.generics, subst):
            owner_expr.inferred_type = dump_type(UnknownType())
            return UnknownType()
        resolved_return = substitute_type(info.return_type, subst)
        owner_expr.inferred_type = dump_type(resolved_return)
        return resolved_return

    def _inspect_expr_type(self, expr: Expr, scope: Dict[str, VarState]) -> Type:
        if isinstance(expr, NameExpr):
            state = scope.get(expr.name)
            if state is None:
                if expr.name in self.variant_to_enum:
                    return NamedType(expr.name)
                imported = self.imported_functions.get(expr.name)
                if imported is not None:
                    return FunctionType(imported.params, imported.return_type)
                self._error(f"unresolved name {expr.name}")
                return UnknownType()
            if state.moved:
                self._error(f"use of moved value {expr.name}")
            return state.ty
        return self._infer_expr(expr, scope)

    def _load_stdlib_primitives(self) -> None:
        self.enums["Option"] = EnumInfo(generics=["T"], variants={"Some": NamedType("T"), "None": None})
        self.enums["Result"] = EnumInfo(
            generics=["T", "E"],
            variants={"Ok": NamedType("T"), "Err": NamedType("E")},
        )
        self.variant_to_enum.update(
            {
                "Some": "Option",
                "None": "Option",
                "Ok": "Result",
                "Err": "Result",
            }
        )
        self.structs.setdefault("FsError", StructInfo(fields={"message": STRING}))
        self.structs.setdefault("ProcessError", StructInfo(fields={"message": STRING}))
        self.structs.setdefault("CliError", StructInfo(fields={"message": STRING}))
        self.structs.setdefault(
            "CompileOptions",
            StructInfo(fields={"command": STRING, "path": STRING, "output": STRING}),
        )
        self.structs.setdefault("UseDecl", StructInfo(fields={"path": STRING, "alias": parse_type("Option[String]")}))
        self.structs.setdefault(
            "Field",
            StructInfo(fields={"name": STRING, "type_name": STRING, "is_public": BOOL}),
        )
        self.structs.setdefault(
            "Param",
            StructInfo(fields={"name": STRING, "type_name": STRING}),
        )
        self.structs.setdefault(
            "FunctionSig",
            StructInfo(
                fields={
                    "name": STRING,
                    "generics": parse_type("Vec[String]"),
                    "params": parse_type("Vec[Param]"),
                    "return_type": parse_type("Option[String]"),
                }
            ),
        )
        self.structs.setdefault(
            "BlockExpr",
            StructInfo(
                fields={
                    "statements": parse_type("Vec[Stmt]"),
                    "final_expr": parse_type("Option[Expr]"),
                }
            ),
        )
        self.structs.setdefault("FunctionDecl", StructInfo(fields={"sig": NamedType("FunctionSig"), "body": parse_type("Option[BlockExpr]"), "is_public": BOOL}))
        self.structs.setdefault(
            "SourceFile",
            StructInfo(fields={"pkg": STRING, "uses": parse_type("Vec[UseDecl]"), "items": parse_type("Vec[Item]")}),
        )
        self.structs.setdefault("SyntaxError", StructInfo(fields={"message": STRING, "line": I32, "column": I32}))
        self.structs.setdefault("ParseError", StructInfo(fields={"message": STRING}))
        self.structs.setdefault("ExecError", StructInfo(fields={"message": STRING}))
        self.structs.setdefault("BackendError", StructInfo(fields={"message": STRING}))
        self.enums.setdefault(
            "Item",
            EnumInfo(
                generics=[],
                variants={
                    "Function": NamedType("FunctionDecl"),
                    "Struct": NamedType("StructDecl"),
                    "Enum": NamedType("EnumDecl"),
                    "Trait": NamedType("TraitDecl"),
                    "Impl": NamedType("ImplDecl"),
                },
            ),
        )

    def _load_use_decls(self, uses: List[UseDecl]) -> None:
        for use in uses:
            local_name = use.alias or use.path.split(".")[-1]
            canonical_name = use.path.split(".")[-1]
            self.type_aliases[local_name] = canonical_name
            imported = self._builtin_for_use(use.path, local_name)
            if imported is not None:
                self.imported_functions[local_name] = imported

    def _builtin_for_use(self, path: str, local_name: str) -> Optional[TraitMethodInfo]:
        std_functions = {
            "std.env.Args": TraitMethodInfo(owner="std.env", generics=[], params=[], return_type=parse_type("Vec[String]")),
            "std.env.Get": TraitMethodInfo(
                owner="std.env",
                generics=[],
                params=[STRING],
                return_type=parse_type("Option[String]"),
            ),
            "std.fs.ReadToString": TraitMethodInfo(
                owner="std.fs",
                generics=[],
                params=[STRING],
                return_type=parse_type("Result[String, FsError]"),
            ),
            "std.fs.WriteTextFile": TraitMethodInfo(
                owner="std.fs",
                generics=[],
                params=[STRING, STRING],
                return_type=parse_type("Result[(), FsError]"),
            ),
            "std.fs.MakeTempDir": TraitMethodInfo(
                owner="std.fs",
                generics=[],
                params=[STRING],
                return_type=parse_type("Result[String, FsError]"),
            ),
            "std.io.println": TraitMethodInfo(owner="std.io", generics=["T"], params=[NamedType("T")], return_type=UNIT),
            "std.io.eprintln": TraitMethodInfo(owner="std.io", generics=["T"], params=[NamedType("T")], return_type=UNIT),
            "std.prelude.len": TraitMethodInfo(owner="std.prelude", generics=["T"], params=[NamedType("T")], return_type=I32),
            "std.prelude.to_string": TraitMethodInfo(owner="std.prelude", generics=[], params=[I32], return_type=STRING),
            "std.prelude.char_at": TraitMethodInfo(owner="std.prelude", generics=[], params=[STRING, I32], return_type=STRING),
            "std.prelude.slice": TraitMethodInfo(owner="std.prelude", generics=[], params=[STRING, I32, I32], return_type=STRING),
            "s.dump_stmt": TraitMethodInfo(
                owner="s",
                generics=[],
                params=[parse_type("Stmt"), STRING],
                return_type=parse_type("Vec[String]"),
            ),
            "s.dump_expr": TraitMethodInfo(
                owner="s",
                generics=[],
                params=[parse_type("Expr")],
                return_type=STRING,
            ),
            "compile.internal.syntax.ReadSource": TraitMethodInfo(
                owner="compile.internal.syntax",
                generics=[],
                params=[STRING],
                return_type=parse_type("Result[String, SyntaxError]"),
            ),
            "compile.internal.syntax.Tokenize": TraitMethodInfo(
                owner="compile.internal.syntax",
                generics=[],
                params=[STRING],
                return_type=parse_type("Result[Vec[Token], SyntaxError]"),
            ),
            "compile.internal.syntax.ParseSource": TraitMethodInfo(
                owner="compile.internal.syntax",
                generics=[],
                params=[STRING],
                return_type=parse_type("Result[SourceFile, SyntaxError]"),
            ),
            "compile.internal.syntax.DumpTokensText": TraitMethodInfo(
                owner="compile.internal.syntax",
                generics=[],
                params=[parse_type("Vec[Token]")],
                return_type=STRING,
            ),
            "compile.internal.syntax.DumpSourceText": TraitMethodInfo(
                owner="compile.internal.syntax",
                generics=[],
                params=[parse_type("SourceFile")],
                return_type=STRING,
            ),
            "compile.internal.typesys.BaseTypeName": TraitMethodInfo(
                owner="compile.internal.typesys",
                generics=[],
                params=[STRING],
                return_type=STRING,
            ),
            "compile.internal.typesys.IsCopyType": TraitMethodInfo(
                owner="compile.internal.typesys",
                generics=[],
                params=[STRING],
                return_type=BOOL,
            ),
            "compile.internal.check.LoadFrontend": TraitMethodInfo(
                owner="compile.internal.check",
                generics=[],
                params=[STRING],
                return_type=STRING,
            ),
            "compile.internal.semantic.CheckText": TraitMethodInfo(
                owner="compile.internal.semantic",
                generics=[],
                params=[STRING],
                return_type=I32,
            ),
            "std.process.Exit": TraitMethodInfo(owner="std.process", generics=[], params=[I32], return_type=UNIT),
            "std.process.RunProcess": TraitMethodInfo(
                owner="std.process",
                generics=[],
                params=[parse_type("Vec[String]")],
                return_type=parse_type("Result[(), ProcessError]"),
            ),
            "__host_build_executable": TraitMethodInfo(
                owner="runtime",
                generics=[],
                params=[STRING, STRING],
                return_type=I32,
            ),
            "compile.internal.compiler.Main": TraitMethodInfo(
                owner="compile.internal.compiler",
                generics=[],
                params=[parse_type("Vec[String]")],
                return_type=I32,
            ),
            "compile.internal.gc.Main": TraitMethodInfo(
                owner="compile.internal.gc",
                generics=[],
                params=[parse_type("Vec[String]")],
                return_type=I32,
            ),
            "compile.internal.build.Main": TraitMethodInfo(
                owner="compile.internal.build",
                generics=[],
                params=[parse_type("Vec[String]")],
                return_type=I32,
            ),
            "compile.internal.build.report.Error": TraitMethodInfo(
                owner="compile.internal.build.report",
                generics=[],
                params=[STRING],
                return_type=UNIT,
            ),
            "compile.internal.build.parse.ParseOptions": TraitMethodInfo(
                owner="compile.internal.build.parse",
                generics=[],
                params=[parse_type("Vec[String]")],
                return_type=parse_type("Result[CompileOptions, ParseError]"),
            ),
            "compile.internal.build.exec.Run": TraitMethodInfo(
                owner="compile.internal.build.exec",
                generics=[],
                params=[parse_type("CompileOptions")],
                return_type=I32,
            ),
            "compile.internal.build.backend.Build": TraitMethodInfo(
                owner="compile.internal.build.backend",
                generics=[],
                params=[STRING, STRING],
                return_type=I32,
            ),
            "compile.internal.build.backend.Run": TraitMethodInfo(
                owner="compile.internal.build.backend",
                generics=[],
                params=[STRING],
                return_type=I32,
            ),
            "compile.internal.tests.test_semantic.RunSemanticSuite": TraitMethodInfo(
                owner="compile.internal.tests.test_semantic",
                generics=[],
                params=[STRING],
                return_type=I32,
            ),
            "compile.internal.tests.test_golden.RunGoldenSuite": TraitMethodInfo(
                owner="compile.internal.tests.test_golden",
                generics=[],
                params=[STRING],
                return_type=I32,
            ),
            "compile.internal.tests.test_mir.RunMirSuite": TraitMethodInfo(
                owner="compile.internal.tests.test_mir",
                generics=[],
                params=[],
                return_type=I32,
            ),
            "compile.internal.build.emit.CheckOk": TraitMethodInfo(
                owner="compile.internal.build.emit",
                generics=[],
                params=[STRING],
                return_type=UNIT,
            ),
            "compile.internal.build.emit.Tokens": TraitMethodInfo(
                owner="compile.internal.build.emit",
                generics=[],
                params=[parse_type("Vec[Token]")],
                return_type=UNIT,
            ),
            "compile.internal.build.emit.Ast": TraitMethodInfo(
                owner="compile.internal.build.emit",
                generics=[],
                params=[parse_type("SourceFile")],
                return_type=UNIT,
            ),
            "compile.internal.build.emit.Built": TraitMethodInfo(
                owner="compile.internal.build.emit",
                generics=[],
                params=[STRING],
                return_type=UNIT,
            ),
            "compile.internal.borrow.AnalyzeBlock": TraitMethodInfo(
                owner="compile.internal.borrow",
                generics=[],
                params=[],
                return_type=I32,
            ),
            "compile.internal.borrow.AnalyzeTrace": TraitMethodInfo(
                owner="compile.internal.borrow",
                generics=[],
                params=[STRING, parse_type("Vec[String]"), STRING],
                return_type=STRING,
            ),
            "compile.internal.borrow.AnalyzeFunction": TraitMethodInfo(
                owner="compile.internal.borrow",
                generics=[],
                params=[STRING, parse_type("Vec[String]"), STRING],
                return_type=STRING,
            ),
            "compile.internal.borrow.AnalyzeExpr": TraitMethodInfo(
                owner="compile.internal.borrow",
                generics=[],
                params=[STRING, STRING],
                return_type=STRING,
            ),
            "compile.internal.mir.LowerFunction": TraitMethodInfo(
                owner="compile.internal.mir",
                generics=[],
                params=[parse_type("FunctionDecl")],
                return_type=STRING,
            ),
            "compile.internal.mir.LowerBlock": TraitMethodInfo(
                owner="compile.internal.mir",
                generics=[],
                params=[parse_type("BlockExpr")],
                return_type=STRING,
            ),
            "compile.internal.mir.TraceBranch": TraitMethodInfo(
                owner="compile.internal.mir",
                generics=[],
                params=[STRING, STRING, STRING],
                return_type=STRING,
            ),
            "compile.internal.mir.TraceLoop": TraitMethodInfo(
                owner="compile.internal.mir",
                generics=[],
                params=[STRING, STRING, STRING],
                return_type=STRING,
            ),
            "compile.internal.mir.TraceMatch": TraitMethodInfo(
                owner="compile.internal.mir",
                generics=[],
                params=[STRING, STRING],
                return_type=STRING,
            ),
            "compile.internal.dispatch.Main": TraitMethodInfo(
                owner="compile.internal.dispatch",
                generics=[],
                params=[parse_type("Vec[String]")],
                return_type=I32,
            ),
            "compile.internal.arch.Init": TraitMethodInfo(
                owner="compile.internal.arch",
                generics=[],
                params=[STRING],
                return_type=STRING,
            ),
            "internal.buildcfg.Check": TraitMethodInfo(
                owner="internal.buildcfg",
                generics=[],
                params=[],
                return_type=STRING,
            ),
            "internal.buildcfg.GOARCH": TraitMethodInfo(
                owner="internal.buildcfg",
                generics=[],
                params=[],
                return_type=STRING,
            ),
            "compile.internal.amd64.Init": TraitMethodInfo(owner="compile.internal.amd64", generics=[], params=[], return_type=UNIT),
            "compile.internal.arm64.Init": TraitMethodInfo(owner="compile.internal.arm64", generics=[], params=[], return_type=UNIT),
            "compile.internal.riscv64.Init": TraitMethodInfo(owner="compile.internal.riscv64", generics=[], params=[], return_type=UNIT),
            "compile.internal.amd64p32.Init": TraitMethodInfo(owner="compile.internal.amd64p32", generics=[], params=[], return_type=UNIT),
            "compile.internal.s390x.Init": TraitMethodInfo(owner="compile.internal.s390x", generics=[], params=[], return_type=UNIT),
            "compile.internal.wasm.Init": TraitMethodInfo(owner="compile.internal.wasm", generics=[], params=[], return_type=UNIT),
        }
        builtin = std_functions.get(path)
        if builtin is None:
            return None
        return TraitMethodInfo(
            owner=builtin.owner,
            generics=builtin.generics,
            params=[self._normalize_type(param) for param in builtin.params],
            return_type=self._normalize_type(builtin.return_type),
            has_receiver=builtin.has_receiver,
            receiver_mode=builtin.receiver_mode,
        )

    def _normalize_type(self, ty: Type) -> Type:
        if isinstance(ty, NamedType):
            name = self.type_aliases.get(ty.name, ty.name)
            return NamedType(name, [self._normalize_type(arg) for arg in ty.args])
        if isinstance(ty, ReferenceType):
            return ReferenceType(self._normalize_type(ty.inner), mutable=ty.mutable)
        if isinstance(ty, SliceType):
            return SliceType(self._normalize_type(ty.inner))
        if isinstance(ty, FunctionType):
            return FunctionType(
                [self._normalize_type(param) for param in ty.params],
                self._normalize_type(ty.return_type or UNIT),
            )
        return ty

    def _variant_name(self, path: str) -> str:
        if "::" in path:
            return path.split("::")[-1]
        if "." in path:
            return path.split(".")[-1]
        return path

    def _receiver_mode(self, param: Optional[Param]) -> str:
        if param is None or param.name != "self":
            return "value"
        if param.type_name.startswith("&mut "):
            return "mut_ref"
        if param.type_name.startswith("&"):
            return "ref"
        return "value"

    def _validate_receiver(self, method: TraitMethodInfo, receiver_type: Type, receiver_expr: Expr, method_name: str) -> None:
        if not method.has_receiver:
            return
        if method.receiver_mode == "mut_ref":
            if isinstance(receiver_type, ReferenceType):
                if not receiver_type.mutable:
                    self._error(f"method {method_name} requires mutable receiver")
            elif not self._can_auto_borrow_mut(receiver_expr):
                self._error(f"method {method_name} requires mutable receiver")
        elif method.receiver_mode == "ref":
            return
        elif method.receiver_mode == "value":
            return

    def _validate_builtin_receiver(
        self,
        method,
        receiver_type: Type,
        receiver_expr: Expr,
        method_name: str,
    ) -> None:
        if self._builtin_receiver_ok(method, receiver_type, receiver_expr):
            return
        if method.receiver_mode == "mut":
            self._error(f"method {method_name} requires mutable receiver")

    def _builtin_receiver_ok(self, method, receiver_type: Type, receiver_expr: Expr) -> bool:
        if method.receiver_mode == "mut":
            if isinstance(receiver_type, ReferenceType):
                return receiver_type.mutable
            if method.receiver_policy == "explicit_mut_ref":
                return False
            return self._can_auto_borrow_mut(receiver_expr)
        if method.receiver_mode == "ref":
            if isinstance(receiver_type, ReferenceType):
                return True
            if method.receiver_policy in {"shared_or_addressable", "addressable"}:
                return self._can_auto_borrow_shared(receiver_expr)
        return True

    def _clone_scope(self, scope: Dict[str, VarState]) -> Dict[str, VarState]:
        return {name: VarState(**vars(state)) for name, state in scope.items()}

    def _merge_back(self, dest: Dict[str, VarState], source: Dict[str, VarState]) -> None:
        for name, state in source.items():
            if name in dest:
                dest[name] = VarState(**vars(state))

    def _join_scopes(
        self,
        dest: Dict[str, VarState],
        left: Dict[str, VarState],
        right: Dict[str, VarState],
    ) -> None:
        for name, original in list(dest.items()):
            l = left.get(name, original)
            r = right.get(name, original)
            dest[name] = VarState(
                ty=l.ty,
                moved=l.moved or r.moved,
                shared_borrows=max(l.shared_borrows, r.shared_borrows),
                mut_borrowed=l.mut_borrowed or r.mut_borrowed,
            )

    def _error(self, message: str) -> None:
        self.diagnostics.append(Diagnostic(message=message))

    def _can_auto_borrow_mut(self, expr: Expr) -> bool:
        return isinstance(expr, (NameExpr, MemberExpr, IndexExpr))

    def _can_auto_borrow_shared(self, expr: Expr) -> bool:
        return isinstance(expr, (NameExpr, MemberExpr, IndexExpr))
