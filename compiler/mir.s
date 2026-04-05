package compiler

use std.option.Option
use std.vec.Vec
use frontend.BlockExpr
use frontend.Expr

struct LocalSlot {
    i32 id,
    String name,
    String kind,
    i32 version,
    Type ty,
}

struct Operand {
    String kind,
    i32 slot,
    String text,
}

struct AssignStmt {
    i32 target,
    String op,
    Vec[Operand] args,
}

struct EvalStmt {
    String op,
    Vec[Operand] args,
}

struct MoveStmt {
    i32 target,
    Operand source,
}

struct CopyStmt {
    i32 target,
    Operand source,
}

struct DropStmt {
    i32 slot,
}

struct ControlEdge {
    String id,
    i32 target,
    Vec[Operand] args,
}

struct Terminator {
    String kind,
    Vec[ControlEdge] edges,
}

struct BasicBlock {
    i32 id,
    Vec[i32] params,
    Vec[String] statements,
    Terminator terminator,
}

struct MIRGraph {
    Vec[BasicBlock] blocks,
    i32 entry,
    i32 exit,
    Vec[LocalSlot] locals,
}

MIRGraph LowerBlock(BlockExpr block, Vec[String] param_names, Vec[TypeBinding] type_env){
    var locals = Vec[LocalSlot]()
    var statements = Vec[String]()
    var next_local = 0

    for name in param_names {
        var ty =
            match FindTypeBinding(type_env, name) {
                :Some(value) => value Option,
                :None => UnknownTypeOf("param") Option,
            }
        locals.push(LocalSlot {
            next_local id,
            name name,
            "param" kind,
            0 version,
            ty ty,
        })
        next_local = next_local + 1
    }

    for stmt in block.statements {
        statements.push("stmt")
    }
    match block.final_expr {
        :Some(_) => statements.push("yield") Option,
        :None => () Option,
    }

    var blocks = Vec[BasicBlock]()
    blocks.push(BasicBlock {
        0 id,
        Vec[i32]() params,
        statements statements,
        Terminator { terminator
            "goto" kind,
            Vec[ControlEdge] { edges
                ControlEdge {
                    "edge:0" id,
                    1 target,
                    Vec[Operand]() args,
                },
            },
        },
    })
    blocks.push(BasicBlock {
        1 id,
        Vec[i32]() params,
        Vec[String]() statements,
        Terminator { terminator
            "return" kind,
            Vec[ControlEdge]() edges,
        },
    })

    MIRGraph {
        blocks blocks,
        0 entry,
        1 exit,
        locals locals,
    }
}
