package compiler

use std.vec.Vec

struct OwnershipDecision {
    Type ty,
    bool copyable,
    bool droppable,
}

struct OwnershipEntry {
    String name,
    OwnershipDecision decision,
}

OwnershipDecision MakeDecision(Type ty) {
    var copyable = IsCopyType(ty)
    OwnershipDecision {
        ty: ty,
        copyable: copyable,
        droppable: !copyable,
    }
}

Vec[OwnershipEntry] MakePlan(Vec[TypeBinding] type_env) {
    var out = Vec[OwnershipEntry]()
    for entry in type_env {
        out.push(OwnershipEntry {
            name: entry.name,
            decision: MakeDecision(entry.value),
        })
    }
    out
}
