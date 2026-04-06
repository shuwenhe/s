package compiler

use compiler.internal.typecheck.IsCopyType
use compiler.internal.typecheck.Type
use compiler.internal.typecheck.TypeBinding
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

func MakeDecision(Type ty) -> OwnershipDecision {
    var copyable = IsCopyType(ty)
    OwnershipDecision {
        ty: ty,
        copyable: copyable,
        droppable: !copyable,
    }
}

func MakePlan(Vec[TypeBinding] type_env) -> Vec[OwnershipEntry] {
    var out = Vec[OwnershipEntry]()
    for entry in type_env {
        out.push(OwnershipEntry {
            name: entry.name,
            decision: MakeDecision(entry.value),
        })
    }
    out
}
