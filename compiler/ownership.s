package compiler

use std.vec.Vec

pub struct OwnershipDecision {
    ty: Type,
    copyable: bool,
    droppable: bool,
}

pub struct OwnershipEntry {
    name: String,
    decision: OwnershipDecision,
}

pub fn make_decision(ty: Type) -> OwnershipDecision {
    let copyable = is_copy_type(ty)
    OwnershipDecision {
        ty: ty,
        copyable: copyable,
        droppable: !copyable,
    }
}

pub fn make_plan(type_env: Vec[TypeBinding]) -> Vec[OwnershipEntry] {
    let out = Vec[OwnershipEntry]()
    for entry in type_env {
        out.push(OwnershipEntry {
            name: entry.name,
            decision: make_decision(entry.value),
        })
    }
    out
}
