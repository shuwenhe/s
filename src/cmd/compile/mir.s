package compiler

use std.option.Option
use std.vec.Vec
use s.BlockExpr
use s.Expr

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

func LowerBlock(BlockExpr block, Vec[String] param_names, Vec[TypeBinding] type_env) -> MIRGraph {
    var locals = Vec[LocalSlot]()
    var statements = Vec[String]()
    var next_local = 0

    for name in param_names {
        var ty =
            match FindTypeBinding(type_env, name) {
                Option::Some(value) => value,
                Option::None => UnknownTypeOf("param"),
            }
        locals.push(LocalSlot {
            id: next_local,
            name: name,
            kind: "param",
            version: 0,
            ty: ty,
        })
        next_local = next_local + 1
    }

    for stmt in block.statements {
        statements.push("stmt")
    }
    match block.final_expr {
        Option::Some(_) => statements.push("yield"),
        Option::None => (),
    }

    var blocks = Vec[BasicBlock]()
    blocks.push(BasicBlock {
        id: 0,
        params: Vec[i32](),
        statements: statements,
        terminator: Terminator {
            kind: "goto",
            edges: Vec[ControlEdge] {
                ControlEdge {
                    id: "edge:0",
                    target: 1,
                    args: Vec[Operand](),
                },
            },
        },
    })
    blocks.push(BasicBlock {
        id: 1,
        params: Vec[i32](),
        statements: Vec[String](),
        terminator: Terminator {
            kind: "return",
            edges: Vec[ControlEdge](),
        },
    })

    MIRGraph {
        blocks: blocks,
        entry: 0,
        exit: 1,
        locals: locals,
    }
}
