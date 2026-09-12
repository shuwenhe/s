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
use compile.internal.mir.mir_operand
use compile.internal.mir.mir_move_stmt
use compile.internal.mir.mir_drop_stmt
use std.slices
func run_mir_suite() int {
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
    blocks := mir_basic_block[]()
    blocks.push(mir_basic_block {
        id: 0,
        label: "entry", statements mir_statement[](), terminator mir_terminator {
            kind: "return", edges mir_control_edge[](),
        },
    })
    graph := mir_graph {
        function_name: "main", blocks blocks, locals mir_local_slot[](), string trace[](), entry 0, exit 0,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
    if block_count(graph) != 1 {
        return 1
    }
    if dump_graph(graph) != "mir main blocks=1 entry=0 exit=0 | bb0(entry) stmts=0 term=return" {
        return 1
    }
    gate_statements := mir_statement[]()
    gate_statements.push(mir_statement::move(mir_move_stmt {
        target: 1, source mir_operand {
            kind: "local", value: "_1", type_name: "box[int]",
        },
    }))
    gate_statements.push(mir_statement::drop(mir_drop_stmt { slot: 1 }))
    gate_blocks := mir_basic_block[]()
    gate_blocks.push(mir_basic_block {
        id: 0,
        label: "entry", statements gate_statements, terminator mir_terminator {
            kind: "return", edges mir_control_edge[](),
        },
    })
    gate_locals := mir_local_slot[]()
    gate_locals.push(mir_local_slot { id: 0, name: "_1", kind: "local", version: 0, type_name: "box[int]", copyable: false })
    gate_locals.push(mir_local_slot { id: 1, name: "_2", kind: "local", version: 0, type_name: "box[int]", copyable: false })
    gate := mir_graph {
        function_name: "ownership_borrow_drop_gate", blocks gate_blocks, locals gate_locals, string trace[](), entry 0, exit 0,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
    if count_mir_moves(gate) != 1 {
        return 1
    }
    if count_mir_drops(gate) != 1 {
        return 1
    }
    0
}

func count_mir_moves(mir_graph graph) int {
    count := 0
    i := 0
    while i < len(graph.blocks) {
        j := 0
        while j < len(graph.blocks[i].statements) {
            switch graph.blocks[i].statements[j] {
                mir_statement::move(_) : count = count + 1
                _ : { }
            }
            j = j + 1
        }
        i = i + 1
    }
    count
}

func count_mir_drops(mir_graph graph) int {
    count := 0
    i := 0
    while i < len(graph.blocks) {
        j := 0
        while j < len(graph.blocks[i].statements) {
            switch graph.blocks[i].statements[j] {
                mir_statement::drop(_) : count = count + 1
                _ : { }
            }
            j = j + 1
        }
        i = i + 1
    }
    count
}
