from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from compiler.ast import (
    BinaryExpr,
    BlockExpr,
    BorrowExpr,
    CallExpr,
    Expr,
    ExprStmt,
    ForExpr,
    IfExpr,
    IndexExpr,
    LetStmt,
    MatchExpr,
    MemberExpr,
    NameExpr,
    ReturnStmt,
    WhileExpr,
)
from compiler.ownership import OwnershipDecision, make_decision
from compiler.typesys import Type, UnknownType, parse_type


@dataclass(frozen=True)
class LocalSlot:
    id: int
    name: str
    kind: str
    version: int = 0
    ty: Type = field(default_factory=UnknownType)


@dataclass(frozen=True)
class Operand:
    kind: str
    value: object


@dataclass(frozen=True)
class AssignStmt:
    target: int
    op: str
    args: tuple[object, ...]


@dataclass(frozen=True)
class EvalStmt:
    op: str
    args: tuple[object, ...]


@dataclass(frozen=True)
class MoveStmt:
    target: int
    source: Operand


@dataclass(frozen=True)
class CopyStmt:
    target: int
    source: Operand


@dataclass(frozen=True)
class DropStmt:
    slot: int


@dataclass(frozen=True)
class ControlEdge:
    id: str
    target: int
    args: tuple[Operand, ...] = ()


@dataclass
class Terminator:
    kind: str
    edges: List[ControlEdge] = field(default_factory=list)

    @property
    def targets(self) -> List[int]:
        return [edge.target for edge in self.edges]

    @property
    def target_args(self) -> List[tuple[Operand, ...]]:
        return [edge.args for edge in self.edges]


@dataclass
class BasicBlock:
    id: int
    params: List[int] = field(default_factory=list)
    statements: List[object] = field(default_factory=list)
    terminator: Terminator = field(default_factory=lambda: Terminator("goto", []))


@dataclass
class MIRGraph:
    blocks: Dict[int, BasicBlock]
    entry: int
    exit: int
    locals: Dict[int, LocalSlot]


def lower_block(
    block: BlockExpr,
    param_names: Optional[List[str]] = None,
    type_env: Optional[Dict[str, Type]] = None,
    ownership_plan: Optional[Dict[str, OwnershipDecision]] = None,
) -> MIRGraph:
    builder = _MIRBuilder(param_names or [], type_env or {}, ownership_plan or {})
    entry, exits = builder.lower_block(block)
    exit_id = builder.new_block()
    for block_id in exits:
        builder.blocks[block_id].terminator = Terminator("goto", [builder.edge(exit_id)])
    return MIRGraph(builder.blocks, entry, exit_id, builder.locals)


class _MIRBuilder:
    def __init__(
        self,
        param_names: List[str],
        type_env: Dict[str, Type],
        ownership_plan: Dict[str, OwnershipDecision],
    ) -> None:
        self.blocks: Dict[int, BasicBlock] = {}
        self.locals: Dict[int, LocalSlot] = {}
        self.name_to_slot: Dict[str, int] = {}
        self.name_versions: Dict[str, int] = {}
        self.type_env = type_env
        self.ownership_plan = ownership_plan
        self.next_block_id = 0
        self.next_local_id = 0
        self.next_edge_id = 0
        for name in param_names:
            self.bind_name(name, "param", self.type_env.get(name, UnknownType()))

    def new_block(self) -> int:
        block_id = self.next_block_id
        self.next_block_id += 1
        self.blocks[block_id] = BasicBlock(block_id)
        return block_id

    def new_temp(self) -> int:
        slot_id = self.next_local_id
        self.next_local_id += 1
        self.locals[slot_id] = LocalSlot(slot_id, f"_t{slot_id}", "temp", 0, UnknownType())
        return slot_id

    def edge(self, target: int, args: tuple[Operand, ...] = (), label: str = "edge") -> ControlEdge:
        edge_id = f"{label}:{self.next_edge_id}"
        self.next_edge_id += 1
        return ControlEdge(edge_id, target, args)

    def bind_name(self, name: str, kind: str, ty: Optional[Type] = None) -> int:
        if kind == "param" and name in self.name_to_slot:
            return self.name_to_slot[name]
        version = self.name_versions.get(name, -1) + 1
        self.name_versions[name] = version
        slot_id = self.next_local_id
        self.next_local_id += 1
        self.locals[slot_id] = LocalSlot(slot_id, name, kind, version, ty or self.type_env.get(name, UnknownType()))
        self.name_to_slot[name] = slot_id
        return slot_id

    def slot_for_name(self, name: str) -> int:
        return self.bind_name(name, "local", self.type_env.get(name, UnknownType()))

    def _decision_for_slot(self, slot_id: int) -> OwnershipDecision:
        slot = self.locals[slot_id]
        if slot.name in self.ownership_plan:
            return self.ownership_plan[slot.name]
        return make_decision(slot.ty)

    def _consume_stmt(self, target: int, value: Operand) -> object:
        if value.kind == "slot":
            decision = self._decision_for_slot(value.value)
            if not decision.copyable:
                return MoveStmt(target, value)
        return CopyStmt(target, value)

    def lower_block(self, block: BlockExpr) -> tuple[int, List[int]]:
        entry = self.new_block()
        current = entry
        for stmt in block.statements:
            current = self._lower_stmt(stmt, current)
        if block.final_expr is None:
            self._emit_drops(current)
            return entry, [current]
        entry, exits = self._lower_tail_expr(block.final_expr, current, entry)
        for block_id in exits:
            self._emit_drops(block_id)
        return entry, exits

    def _lower_stmt(self, stmt, current: int) -> int:
        if isinstance(stmt, LetStmt):
            inferred = parse_type(stmt.type_name) if stmt.type_name else self._infer_expr_type(stmt.value)
            slot = self.bind_name(stmt.name, "local", inferred)
            value = self._lower_expr(stmt.value, current)
            self.blocks[current].statements.append(self._consume_stmt(slot, value))
            return current
        if isinstance(stmt, ExprStmt):
            self._lower_expr(stmt.expr, current)
            return current
        if isinstance(stmt, ReturnStmt):
            if stmt.value is not None:
                value = self._lower_expr(stmt.value, current)
                self.blocks[current].statements.append(EvalStmt("return", (value,)))
            else:
                self.blocks[current].statements.append(EvalStmt("return", (Operand("unit", ()),)))
            return current
        self.blocks[current].statements.append(EvalStmt("stmt", (stmt,)))
        return current

    def _lower_tail_expr(self, expr: Expr, current: int, entry: int) -> tuple[int, List[int]]:
        if isinstance(expr, IfExpr):
            cond = self._lower_expr(expr.condition, current)
            then_entry, then_exits = self.lower_block(expr.then_branch)
            else_entry = self.new_block()
            else_exits = [else_entry]
            then_value: Operand | None = None
            else_value: Operand | None = None
            if expr.else_branch is not None:
                if isinstance(expr.else_branch, BlockExpr):
                    else_entry, else_exits = self.lower_block(expr.else_branch)
                else:
                    else_value = self._lower_expr(expr.else_branch, else_entry)
                    self.blocks[else_entry].statements.append(EvalStmt("yield", (else_value,)))
            for block_id in then_exits:
                for stmt in reversed(self.blocks[block_id].statements):
                    if isinstance(stmt, EvalStmt) and stmt.op == "yield":
                        then_value = stmt.args[0]
                        break
            for block_id in else_exits:
                for stmt in reversed(self.blocks[block_id].statements):
                    if isinstance(stmt, EvalStmt) and stmt.op == "yield":
                        else_value = stmt.args[0]
                        break
            self.blocks[current].statements.append(EvalStmt("branch_if", (cond,)))
            join_block = self.new_block()
            join_param = self.new_temp()
            self.blocks[join_block].params.append(join_param)
            self.blocks[current].terminator = Terminator(
                "branch",
                [
                    self.edge(then_entry, label="if_then"),
                    self.edge(else_entry, label="if_else"),
                ],
            )
            if then_value is not None and else_value is not None:
                self.locals[join_param] = LocalSlot(
                    join_param,
                    f"_join{join_param}",
                    "param",
                    0,
                    self._operand_type(then_value),
                )
                for block_ids, arg, label in (
                    (then_exits, then_value, "if_join_then"),
                    (else_exits, else_value, "if_join_else"),
                ):
                    for exit_id in block_ids:
                        self.blocks[exit_id].terminator = Terminator("goto", [self.edge(join_block, (arg,), label)])
                self.blocks[join_block].statements.append(EvalStmt("yield", (Operand("slot", join_param),)))
            else:
                for block_id in then_exits + else_exits:
                    self.blocks[block_id].terminator = Terminator("goto", [self.edge(join_block, label="if_join")])
            return entry, [join_block]
        if isinstance(expr, MatchExpr):
            subject = self._lower_expr(expr.subject, current)
            self.blocks[current].statements.append(EvalStmt("match_subject", (subject,)))
            exits: List[int] = []
            arm_targets: List[int] = []
            arm_values: List[Operand] = []
            for arm in expr.arms:
                arm_block = self.new_block()
                value = self._lower_expr(arm.expr, arm_block)
                self.blocks[arm_block].statements.append(EvalStmt("match_arm", (arm.pattern, value)))
                exits.append(arm_block)
                arm_targets.append(arm_block)
                arm_values.append(value)
            join_block = self.new_block()
            join_param = self.new_temp()
            self.blocks[join_block].params.append(join_param)
            self.blocks[current].terminator = Terminator(
                "switch",
                [self.edge(target, label=f"match_arm_{index}") for index, target in enumerate(arm_targets)],
            )
            if arm_values:
                self.locals[join_param] = LocalSlot(
                    join_param,
                    f"_join{join_param}",
                    "param",
                    0,
                    self._operand_type(arm_values[0]),
                )
                for block_id, arg in zip(exits, arm_values):
                    self.blocks[block_id].terminator = Terminator(
                        "goto",
                        [self.edge(join_block, (arg,), f"match_join_{block_id}")],
                    )
                self.blocks[join_block].statements.append(EvalStmt("yield", (Operand("slot", join_param),)))
            else:
                for block_id in exits:
                    self.blocks[block_id].terminator = Terminator("goto", [self.edge(join_block, label="match_join")])
            return entry, [join_block]
        if isinstance(expr, WhileExpr):
            cond_slot = self._lower_expr(expr.condition, current)
            body_entry, body_exits = self.lower_block(expr.body)
            after = self.new_block()
            self.blocks[current].statements.append(EvalStmt("while_cond", (cond_slot,)))
            self.blocks[current].terminator = Terminator(
                "branch",
                [
                    self.edge(body_entry, label="while_body"),
                    self.edge(after, label="while_exit"),
                ],
            )
            for block_id in body_exits:
                self.blocks[block_id].terminator = Terminator("goto", [self.edge(current, label="while_back")])
            return entry, [after]
        if isinstance(expr, ForExpr):
            iter_slot = self._lower_expr(expr.iterable, current)
            iter_var = self.bind_name(expr.name, "loop", self._infer_iter_type(iter_slot))
            body_entry, body_exits = self.lower_block(expr.body)
            after = self.new_block()
            self.blocks[current].statements.append(EvalStmt("for_iter", (iter_var, iter_slot)))
            self.blocks[current].terminator = Terminator(
                "branch",
                [
                    self.edge(body_entry, label="for_body"),
                    self.edge(after, label="for_exit"),
                ],
            )
            for block_id in body_exits:
                self.blocks[block_id].terminator = Terminator("goto", [self.edge(current, label="for_back")])
            return entry, [after]
        value = self._lower_expr(expr, current)
        self.blocks[current].statements.append(EvalStmt("yield", (value,)))
        return entry, [current]

    def _lower_expr(self, expr: Expr, current: int) -> Operand:
        if isinstance(expr, NameExpr):
            return Operand("slot", self.slot_for_name(expr.name))
        if isinstance(expr, BorrowExpr):
            target = self._lower_expr(expr.target, current)
            slot = self.new_temp()
            self.blocks[current].statements.append(
                AssignStmt(slot, "borrow_mut" if expr.mutable else "borrow", (target,))
            )
            self.locals[slot] = LocalSlot(slot, f"_t{slot}", "temp", 0, self._operand_type(target))
            return Operand("slot", slot)
        if isinstance(expr, BinaryExpr):
            left = self._lower_expr(expr.left, current)
            right = self._lower_expr(expr.right, current)
            slot = self.new_temp()
            self.blocks[current].statements.append(AssignStmt(slot, f"binary:{expr.op}", (left, right)))
            self.locals[slot] = LocalSlot(slot, f"_t{slot}", "temp", 0, self._infer_binary_type(expr.op, left, right))
            return Operand("slot", slot)
        if isinstance(expr, MemberExpr):
            target = self._lower_expr(expr.target, current)
            slot = self.new_temp()
            self.blocks[current].statements.append(AssignStmt(slot, "member", (target, expr.member)))
            self.locals[slot] = LocalSlot(slot, f"_t{slot}", "temp", 0, UnknownType(f"member:{expr.member}"))
            return Operand("slot", slot)
        if isinstance(expr, IndexExpr):
            target = self._lower_expr(expr.target, current)
            index = self._lower_expr(expr.index, current)
            slot = self.new_temp()
            self.blocks[current].statements.append(AssignStmt(slot, "index", (target, index)))
            self.locals[slot] = LocalSlot(slot, f"_t{slot}", "temp", 0, UnknownType("index"))
            return Operand("slot", slot)
        if isinstance(expr, CallExpr):
            callee = self._lower_expr(expr.callee, current)
            args = tuple(self._lower_expr(arg, current) for arg in expr.args)
            slot = self.new_temp()
            self.blocks[current].statements.append(AssignStmt(slot, "call", (callee, *args)))
            self.locals[slot] = LocalSlot(slot, f"_t{slot}", "temp", 0, UnknownType("call"))
            return Operand("slot", slot)
        if isinstance(expr, BlockExpr):
            slot = self.new_temp()
            self.blocks[current].statements.append(AssignStmt(slot, "block", (expr,)))
            self.locals[slot] = LocalSlot(slot, f"_t{slot}", "temp", 0, UnknownType("block"))
            return Operand("slot", slot)
        if hasattr(expr, "value"):
            return Operand("literal", getattr(expr, "value"))
        slot = self.new_temp()
        self.blocks[current].statements.append(AssignStmt(slot, "expr", (expr,)))
        self.locals[slot] = LocalSlot(slot, f"_t{slot}", "temp", 0, self._infer_expr_type(expr))
        return Operand("slot", slot)

    def _emit_drops(self, block_id: int) -> None:
        for slot_id, slot in sorted(self.locals.items(), reverse=True):
            if slot.kind in {"local", "loop", "param"} and self._decision_for_slot(slot_id).droppable:
                self.blocks[block_id].statements.append(DropStmt(slot_id))

    def _operand_type(self, operand: Operand) -> Type:
        if operand.kind == "slot":
            return self.locals[operand.value].ty
        return UnknownType("literal")

    def _infer_expr_type(self, expr: Expr) -> Type:
        if hasattr(expr, "inferred_type") and getattr(expr, "inferred_type", None):
            return parse_type(expr.inferred_type)
        if hasattr(expr, "value") and isinstance(getattr(expr, "value"), str) and getattr(expr, "value").isdigit():
            return parse_type("i32")
        return UnknownType("expr")

    def _infer_binary_type(self, op: str, left: Operand, right: Operand) -> Type:
        if op in {"+", "-", "*", "/", "%"}:
            return parse_type("i32")
        if op in {"==", "!=", "<", "<=", ">", ">=", "&&", "||"}:
            return parse_type("bool")
        return UnknownType("binary")

    def _infer_iter_type(self, operand: Operand) -> Type:
        if operand.kind == "slot":
            ty = self.locals[operand.value].ty
            if hasattr(ty, "args") and getattr(ty, "args", None):
                return ty.args[0]
        return UnknownType("iter_item")
