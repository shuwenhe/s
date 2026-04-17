from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional

from compiler.ast import ExprStmt, LetStmt, ReturnStmt
from compiler.mir import CopyStmt, DropStmt, EvalStmt, LocalSlot, MIRGraph, MoveStmt, Operand, lower_block
from compiler.ownership import OwnershipDecision
from compiler.typesys import Type, is_copy_type


@dataclass
class BorrowDiagnostic:
    message: str


@dataclass
class VarState:
    ty: Type
    moved: bool = False
    shared_borrows: int = 0
    mut_borrowed: bool = False


def analyze_block(
    block,
    initial: Dict[str, VarState],
    ownership_plan: Optional[Dict[str, OwnershipDecision]] = None,
)  List[BorrowDiagnostic]:
    type_env = {name: state.ty for name, state in initial.items()}
    return analyze_mir(lower_block(block, list(initial.keys()), type_env, ownership_plan), initial)


def analyze_mir(graph: MIRGraph, initial: Dict[str, VarState])  List[BorrowDiagnostic]:
    diagnostics: List[BorrowDiagnostic] = []
    in_states: Dict[int, Dict[str, VarState]] = {graph.entry: _clone_scope(initial)}
    worklist = [graph.entry]
    while worklist:
        block_id = worklist.pop(0)
        state = _clone_scope(in_states[block_id])
        block = graph.blocks[block_id]
        for stmt in block.statements:
            _apply_stmt(stmt, state, diagnostics, graph.locals)
        for edge in block.terminator.edges:
            next_input = _clone_scope(state)
            if block_id != edge.target:
                _apply_block_args(next_input, graph.blocks[edge.target], edge.args, diagnostics, graph.locals)
            next_state = in_states.get(edge.target)
            if next_state is None:
                in_states[edge.target] = next_input
                worklist.append(edge.target)
            else:
                merged = _join_scopes(next_state, next_input)
                if merged != next_state:
                    in_states[edge.target] = merged
                    worklist.append(edge.target)
    return diagnostics


def _apply_stmt(
    stmt,
    scope: Dict[str, VarState],
    diagnostics: List[BorrowDiagnostic],
    locals_map: Dict[int, LocalSlot],
)  None:
    if isinstance(stmt, MoveStmt):
        _apply_move(stmt, scope, diagnostics, locals_map)
        return
    if isinstance(stmt, CopyStmt):
        _apply_copy(stmt, scope, diagnostics, locals_map)
        return
    if isinstance(stmt, DropStmt):
        _apply_drop(stmt, scope, locals_map)
        return
    if isinstance(stmt, EvalStmt):
        _apply_eval(stmt, scope, diagnostics, locals_map)
        return
    if isinstance(stmt, tuple):
        tag = stmt[0]
        if tag in {"if_cond", "match_subject", "final_expr", "else_expr"}:
            _apply_expr(stmt[-1], scope, diagnostics)
        elif tag == "match_arm":
            _apply_expr(stmt[2], scope, diagnostics)
        elif tag == "while_cond":
            _apply_expr(stmt[1], scope, diagnostics)
        elif tag == "for_iter":
            _apply_expr(stmt[2], scope, diagnostics)


def _apply_move(
    stmt: MoveStmt,
    scope: Dict[str, VarState],
    diagnostics: List[BorrowDiagnostic],
    locals_map: Dict[int, LocalSlot],
)  None:
    _apply_operand(stmt.source, scope, diagnostics, locals_map, consume=True)

def _apply_copy(
    stmt: CopyStmt,
    scope: Dict[str, VarState],
    diagnostics: List[BorrowDiagnostic],
    locals_map: Dict[int, LocalSlot],
)  None:
    _apply_operand(stmt.source, scope, diagnostics, locals_map, consume=False)


def _apply_drop(stmt: DropStmt, scope: Dict[str, VarState], locals_map: Dict[int, LocalSlot])  None:
    slot_name = _slot_name(stmt.slot, locals_map)
    if slot_name is None or slot_name not in scope:
        return
    scope[slot_name].shared_borrows = 0
    scope[slot_name].mut_borrowed = False


def _apply_eval(
    stmt: EvalStmt,
    scope: Dict[str, VarState],
    diagnostics: List[BorrowDiagnostic],
    locals_map: Dict[int, LocalSlot],
)  None:
    for arg in stmt.args:
        _apply_operand(arg, scope, diagnostics, locals_map, consume=True)


def _apply_block_args(
    scope: Dict[str, VarState],
    block,
    args,
    diagnostics: List[BorrowDiagnostic],
    locals_map: Dict[int, LocalSlot],
)  None:
    for slot_id, operand in zip(block.params, args):
        slot_name = _slot_name(slot_id, locals_map)
        if slot_name is None:
            continue
        _apply_operand(operand, scope, diagnostics, locals_map, consume=False)


def _apply_operand(value, scope: Dict[str, VarState], diagnostics: List[BorrowDiagnostic], locals_map, consume: bool)  None:
    if isinstance(value, Operand):
        if value.kind == "slot":
            slot_name = _slot_name(value.value, locals_map)
            if slot_name is not None:
                if slot_name in scope:
                    if consume:
                        _consume_name(slot_name, scope, diagnostics)
                    else:
                        _inspect_name(slot_name, scope, diagnostics)
        return
    if isinstance(value, tuple):
        for item in value:
            _apply_operand(item, scope, diagnostics, locals_map, consume)


def _apply_expr(expr, scope: Dict[str, VarState], diagnostics: List[BorrowDiagnostic])  None:
    from compiler.ast import BinaryExpr, BlockExpr, BorrowExpr, CallExpr, IfExpr, IndexExpr, MatchExpr, MemberExpr, NameExpr

    if isinstance(expr, NameExpr):
        _consume_name(expr.name, scope, diagnostics)
        return
    if isinstance(expr, BorrowExpr) and isinstance(expr.target, NameExpr):
        state = scope.get(expr.target.name)
        if state is None:
            return
        if state.moved:
            diagnostics.append(BorrowDiagnostic(f"borrow of moved value {expr.target.name}"))
        if expr.mutable:
            if state.shared_borrows > 0 or state.mut_borrowed:
                diagnostics.append(BorrowDiagnostic(f"cannot mutably borrow {expr.target.name} while borrowed"))
            state.mut_borrowed = True
        else:
            if state.mut_borrowed:
                diagnostics.append(BorrowDiagnostic(f"cannot immutably borrow {expr.target.name} while mutably borrowed"))
            state.shared_borrows += 1
        return
    if isinstance(expr, BinaryExpr):
        _apply_expr(expr.left, scope, diagnostics)
        _apply_expr(expr.right, scope, diagnostics)
        return
    if isinstance(expr, CallExpr):
        if isinstance(expr.callee, MemberExpr):
            _inspect_expr(expr.callee.target, scope, diagnostics)
        else:
            _apply_expr(expr.callee, scope, diagnostics)
        for arg in expr.args:
            _apply_expr(arg, scope, diagnostics)
        return
    if isinstance(expr, MemberExpr):
        _inspect_expr(expr.target, scope, diagnostics)
        return
    if isinstance(expr, IndexExpr):
        _inspect_expr(expr.target, scope, diagnostics)
        _apply_expr(expr.index, scope, diagnostics)
        return
    if isinstance(expr, MatchExpr):
        _apply_expr(expr.subject, scope, diagnostics)
        for arm in expr.arms:
            arm_scope = _clone_scope(scope)
            _apply_expr(arm.expr, arm_scope, diagnostics)
        return
    if isinstance(expr, IfExpr):
        _apply_expr(expr.condition, scope, diagnostics)
        then_scope = _clone_scope(scope)
        _apply_block_expr(expr.then_branch, then_scope, diagnostics)
        if expr.else_branch is not None:
            else_scope = _clone_scope(scope)
            _apply_expr(expr.else_branch, else_scope, diagnostics)
        return
    if isinstance(expr, BlockExpr):
        _apply_block_expr(expr, scope, diagnostics)


def _apply_block_expr(block, scope: Dict[str, VarState], diagnostics: List[BorrowDiagnostic])  None:
    for stmt in block.statements:
        if isinstance(stmt, LetStmt) and isinstance(stmt.value, NameExpr):
            _consume_name(stmt.value.name, scope, diagnostics)
        elif isinstance(stmt, ExprStmt):
            _apply_expr(stmt.expr, scope, diagnostics)
        elif isinstance(stmt, ReturnStmt) and stmt.value is not None:
            _apply_expr(stmt.value, scope, diagnostics)
    if block.final_expr is not None:
        _apply_expr(block.final_expr, scope, diagnostics)


def _join_scopes(left: Dict[str, VarState], right: Dict[str, VarState])  Dict[str, VarState]:
    result = _clone_scope(left)
    for name, state in right.items():
        if name not in result:
            result[name] = VarState(**vars(state))
            continue
        current = result[name]
        result[name] = VarState(
            ty=current.ty,
            moved=current.moved or state.moved,
            shared_borrows=max(current.shared_borrows, state.shared_borrows),
            mut_borrowed=current.mut_borrowed or state.mut_borrowed,
        )
    return result


def _clone_scope(scope: Dict[str, VarState])  Dict[str, VarState]:
    return {name: VarState(**vars(state)) for name, state in scope.items()}


def _consume_name(name: str, scope: Dict[str, VarState], diagnostics: List[BorrowDiagnostic])  None:
    state = scope.get(name)
    if state is None:
        return
    if state.moved:
        diagnostics.append(BorrowDiagnostic(f"use of moved value {name}"))
    if not is_copy_type(state.ty):
        state.moved = True


def _inspect_expr(expr, scope: Dict[str, VarState], diagnostics: List[BorrowDiagnostic])  None:
    from compiler.ast import IndexExpr, MemberExpr, NameExpr

    if isinstance(expr, NameExpr):
        state = scope.get(expr.name)
        if state is not None and state.moved:
            diagnostics.append(BorrowDiagnostic(f"use of moved value {expr.name}"))
        return
    if isinstance(expr, MemberExpr):
        _inspect_expr(expr.target, scope, diagnostics)
        return
    if isinstance(expr, IndexExpr):
        _inspect_expr(expr.target, scope, diagnostics)
        _apply_expr(expr.index, scope, diagnostics)


def _inspect_name(name: str, scope: Dict[str, VarState], diagnostics: List[BorrowDiagnostic])  None:
    state = scope.get(name)
    if state is not None and state.moved:
        diagnostics.append(BorrowDiagnostic(f"use of moved value {name}"))


def _slot_name(slot_id: int, locals_map: Dict[int, LocalSlot])  str | None:
    slot = locals_map.get(slot_id)
    if slot is None:
        return None
    return slot.name
