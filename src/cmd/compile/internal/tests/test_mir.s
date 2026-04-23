package compile.internal.tests.test_mir

use compile.internal.mir.trace_branch
use compile.internal.mir.dump_graph
use compile.internal.mir.block_count
use compile.internal.mir.trace_loop
use compile.internal.mir.trace_switch
use compile.internal.mir.mir_graph
use compile.internal.mir.mir_basic_block
use compile.internal.mir.mir_control_edge
use compile.internal.mir.mir_local_slot
use compile.internal.mir.mir_terminator
use compile.internal.mir.mir_statement
use std.vec.vec

func run_mir_suite() int32 {
    if trace_branch("flag", "then", "else") != "branch flag |   then then |   else else" {
        return 1
    }
    if trace_loop("while", "cond", "body") != "while cond |   body body" {
        return 1
    }
    if trace_switch("value", "arms") != "switch value | arms" {
        return 1
    }
    if trace_switch("value", "") != "switch value" {
        return 1
    }

    var blocks = vec[mir_basic_block]()
    blocks.push(mir_basic_block {
        id: 0,
        label: "entry",
        statements: vec[mir_statement](),
        terminator: mir_terminator {
            kind: "return",
            edges: vec[mir_control_edge](),
        },
    })
    var graph = mir_graph {
        function_name: "main",
        blocks: blocks,
        locals: vec[mir_local_slot](),
        trace: vec[string](),
        entry: 0,
        exit: 0,
    }

    if block_count(graph) != 1 {
        return 1
    }

    if dump_graph(graph) != "mir main blocks=1 entry=0 exit=0 | bb0(entry) stmts=0 term=return" {
        return 1
    }

    0
}
