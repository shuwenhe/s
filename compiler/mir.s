package compiler

use std.option.Option
use std.vec.Vec
use frontend.BlockExpr
use frontend.Expr

struct LocalSlot {
    id: i32,
    name: String,
    kind: String,
    version: i32,
    ty: Type,
}

struct Operand {
    kind: String,
    slot: i32,
    text: String,
}

struct AssignStmt {
    target: i32,
    op: String,
    args: Vec[Operand],
}

struct EvalStmt {
    op: String,
    args: Vec[Operand],
}

struct MoveStmt {
    target: i32,
    source: Operand,
}

struct CopyStmt {
    target: i32,
    source: Operand,
}

struct DropStmt {
    slot: i32,
}

struct ControlEdge {
    id: String,
    target: i32,
    args: Vec[Operand],
}

struct Terminator {
    kind: String,
    edges: Vec[ControlEdge],
}

struct BasicBlock {
    id: i32,
    params: Vec[i32],
    statements: Vec[String],
    terminator: Terminator,
}

struct MIRGraph {
    blocks: Vec[BasicBlock],
    entry: i32,
    exit: i32,
    locals: Vec[LocalSlot],
}

fn LowerBlock(block: BlockExpr, param_names: Vec[String], type_env: Vec[TypeBinding]) -> MIRGraph {
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
