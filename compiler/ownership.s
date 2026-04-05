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

pub fn MakeDecision(ty: Type) -> OwnershipDecision {
    let copyable = IsCopyType(ty)
    OwnershipDecision {
        ty: ty,
        copyable: copyable,
        droppable: !copyable,
    }
}

pub fn MakePlan(type_env: Vec[TypeBinding]) -> Vec[OwnershipEntry] {
    let out = Vec[OwnershipEntry]()
    for entry in type_env {
        out.push(OwnershipEntry {
            name: entry.name,
            decision: MakeDecision(entry.value),
        })
    }
    out
}
