from __future__ import annotations

from dataclasses import dataclass
from typing import dict, list, optional

from compiler.ast import exprstmt, letstmt, returnstmt
from compiler.mir import copystmt, dropstmt, evalstmt, localslot, mirgraph, movestmt, operand, lower_block
from compiler.ownership import ownershipdecision
from compiler.typesys import type, is_copy_type


@dataclass
class borrowdiagnostic:
    message: str


@dataclass
class varstate:
    ty: type
    moved: bool = false
    shared_borrows: int = 0
    mut_borrowed: bool = false


def analyze_block(
    block,
    initial: dict[str, varstate],
    ownership_plan: optional[dict[str, ownershipdecision]] = none,
) -> list[borrowdiagnostic]:
    type_env = {name: state.ty for name, state in initial.items()}
    return analyze_mir(lower_block(block, list(initial.keys()), type_env, ownership_plan), initial)


def analyze_mir(graph: mirgraph, initial: dict[str, varstate]) -> list[borrowdiagnostic]:
    diagnostics: list[borrowdiagnostic] = []
    in_states: dict[int, dict[str, varstate]] = {graph.entry: _clone_scope(initial)}
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
            if next_state is none:
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
    scope: dict[str, varstate],
    diagnostics: list[borrowdiagnostic],
    locals_map: dict[int, localslot],
) -> none:
    if isinstance(stmt, movestmt):
        _apply_move(stmt, scope, diagnostics, locals_map)
        return
    if isinstance(stmt, copystmt):
        _apply_copy(stmt, scope, diagnostics, locals_map)
        return
    if isinstance(stmt, dropstmt):
        _apply_drop(stmt, scope, locals_map)
        return
    if isinstance(stmt, evalstmt):
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
    stmt: movestmt,
    scope: dict[str, varstate],
    diagnostics: list[borrowdiagnostic],
    locals_map: dict[int, localslot],
) -> none:
    _apply_operand(stmt.source, scope, diagnostics, locals_map, consume=true)

def _apply_copy(
    stmt: copystmt,
    scope: dict[str, varstate],
    diagnostics: list[borrowdiagnostic],
    locals_map: dict[int, localslot],
) -> none:
    _apply_operand(stmt.source, scope, diagnostics, locals_map, consume=false)


def _apply_drop(stmt: dropstmt, scope: dict[str, varstate], locals_map: dict[int, localslot]) -> none:
    slot_name = _slot_name(stmt.slot, locals_map)
    if slot_name is none or slot_name not in scope:
        return
    scope[slot_name].shared_borrows = 0
    scope[slot_name].mut_borrowed = false


def _apply_eval(
    stmt: evalstmt,
    scope: dict[str, varstate],
    diagnostics: list[borrowdiagnostic],
    locals_map: dict[int, localslot],
) -> none:
    for arg in stmt.args:
        _apply_operand(arg, scope, diagnostics, locals_map, consume=true)


def _apply_block_args(
    scope: dict[str, varstate],
    block,
    args,
    diagnostics: list[borrowdiagnostic],
    locals_map: dict[int, localslot],
) -> none:
    for slot_id, operand in zip(block.params, args):
        slot_name = _slot_name(slot_id, locals_map)
        if slot_name is none:
            continue
        _apply_operand(operand, scope, diagnostics, locals_map, consume=false)


def _apply_operand(value, scope: dict[str, varstate], diagnostics: list[borrowdiagnostic], locals_map, consume: bool) -> none:
    if isinstance(value, operand):
        if value.kind == "slot":
            slot_name = _slot_name(value.value, locals_map)
            if slot_name is not none:
                if slot_name in scope:
                    if consume:
                        _consume_name(slot_name, scope, diagnostics)
                    else:
                        _inspect_name(slot_name, scope, diagnostics)
        return
    if isinstance(value, tuple):
        for item in value:
            _apply_operand(item, scope, diagnostics, locals_map, consume)


def _apply_expr(expr, scope: dict[str, varstate], diagnostics: list[borrowdiagnostic]) -> none:
    from compiler.ast import binaryexpr, blockexpr, borrowexpr, callexpr, ifexpr, indexexpr, switchexpr, memberexpr, nameexpr, structliteralexpr, unaryexpr

    if isinstance(expr, nameexpr):
        _consume_name(expr.name, scope, diagnostics)
        return
    if isinstance(expr, borrowexpr) and isinstance(expr.target, nameexpr):
        state = scope.get(expr.target.name)
        if state is none:
            return
        if state.moved:
            diagnostics.append(borrowdiagnostic(f"borrow of moved value {expr.target.name}"))
        if expr.mutable:
            if state.shared_borrows > 0 or state.mut_borrowed:
                diagnostics.append(borrowdiagnostic(f"cannot mutably borrow {expr.target.name} while borrowed"))
            state.mut_borrowed = true
        else:
            if state.mut_borrowed:
                diagnostics.append(borrowdiagnostic(f"cannot immutably borrow {expr.target.name} while mutably borrowed"))
            state.shared_borrows += 1
        return
    if isinstance(expr, binaryexpr):
        _apply_expr(expr.left, scope, diagnostics)
        _apply_expr(expr.right, scope, diagnostics)
        return
    if isinstance(expr, unaryexpr):
        _apply_expr(expr.operand, scope, diagnostics)
        return
    if isinstance(expr, callexpr):
        if isinstance(expr.callee, memberexpr):
            _inspect_expr(expr.callee.target, scope, diagnostics)
        else:
            _apply_expr(expr.callee, scope, diagnostics)
        for arg in expr.args:
            _apply_expr(arg, scope, diagnostics)
        return
    if isinstance(expr, structliteralexpr):
        _apply_expr(expr.callee, scope, diagnostics)
        for field in expr.fields:
            _apply_expr(field.value, scope, diagnostics)
        return
    if isinstance(expr, memberexpr):
        _inspect_expr(expr.target, scope, diagnostics)
        return
    if isinstance(expr, indexexpr):
        _inspect_expr(expr.target, scope, diagnostics)
        _apply_expr(expr.index, scope, diagnostics)
        return
    if isinstance(expr, switchexpr):
        _apply_expr(expr.subject, scope, diagnostics)
        for arm in expr.arms:
            arm_scope = _clone_scope(scope)
            _apply_expr(arm.expr, arm_scope, diagnostics)
        return
    if isinstance(expr, ifexpr):
        _apply_expr(expr.condition, scope, diagnostics)
        then_scope = _clone_scope(scope)
        _apply_block_expr(expr.then_branch, then_scope, diagnostics)
        if expr.else_branch is not none:
            else_scope = _clone_scope(scope)
            _apply_expr(expr.else_branch, else_scope, diagnostics)
        return
    if isinstance(expr, blockexpr):
        _apply_block_expr(expr, scope, diagnostics)


def _apply_block_expr(block, scope: dict[str, varstate], diagnostics: list[borrowdiagnostic]) -> none:
    for stmt in block.statements:
        if isinstance(stmt, letstmt) and isinstance(stmt.value, nameexpr):
            _consume_name(stmt.value.name, scope, diagnostics)
        elif isinstance(stmt, exprstmt):
            _apply_expr(stmt.expr, scope, diagnostics)
        elif isinstance(stmt, returnstmt) and stmt.value is not none:
            _apply_expr(stmt.value, scope, diagnostics)
    if block.final_expr is not none:
        _apply_expr(block.final_expr, scope, diagnostics)


def _join_scopes(left: dict[str, varstate], right: dict[str, varstate]) -> dict[str, varstate]:
    result = _clone_scope(left)
    for name, state in right.items():
        if name not in result:
            result[name] = varstate(**vars(state))
            continue
        current = result[name]
        result[name] = varstate(
            ty=current.ty,
            moved=current.moved or state.moved,
            shared_borrows=max(current.shared_borrows, state.shared_borrows),
            mut_borrowed=current.mut_borrowed or state.mut_borrowed,
        )
    return result


def _clone_scope(scope: dict[str, varstate]) -> dict[str, varstate]:
    return {name: varstate(**vars(state)) for name, state in scope.items()}


def _consume_name(name: str, scope: dict[str, varstate], diagnostics: list[borrowdiagnostic]) -> none:
    state = scope.get(name)
    if state is none:
        return
    if state.moved:
        diagnostics.append(borrowdiagnostic(f"use of moved value {name}"))
    if not is_copy_type(state.ty):
        state.moved = true


def _inspect_expr(expr, scope: dict[str, varstate], diagnostics: list[borrowdiagnostic]) -> none:
    from compiler.ast import indexexpr, memberexpr, nameexpr

    if isinstance(expr, nameexpr):
        state = scope.get(expr.name)
        if state is not none and state.moved:
            diagnostics.append(borrowdiagnostic(f"use of moved value {expr.name}"))
        return
    if isinstance(expr, memberexpr):
        _inspect_expr(expr.target, scope, diagnostics)
        return
    if isinstance(expr, indexexpr):
        _inspect_expr(expr.target, scope, diagnostics)
        _apply_expr(expr.index, scope, diagnostics)


def _inspect_name(name: str, scope: dict[str, varstate], diagnostics: list[borrowdiagnostic]) -> none:
    state = scope.get(name)
    if state is not none and state.moved:
        diagnostics.append(borrowdiagnostic(f"use of moved value {name}"))


def _slot_name(slot_id: int, locals_map: dict[int, localslot]) -> str | none:
    slot = locals_map.get(slot_id)
    if slot is none:
        return none
    return slot.name
