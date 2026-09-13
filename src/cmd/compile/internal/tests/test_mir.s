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
use compile.internal.mir.mir_eval_stmt
use compile.internal.mir.mir_move_stmt
use compile.internal.mir.mir_drop_stmt
use compile.internal.mir.mir_place
use compile.internal.mir.mir_place_projection
use compile.internal.mir.mir_borrow_stmt
use compile.internal.mir.mir_ref_assign_stmt
use compile.internal.mir.mir_ref_use_stmt
use compile.internal.mir.build_mir_point_map
use compile.internal.mir.mir_point_id
use compile.internal.mir.mir_point_count
use compile.internal.mir.mir_point_text
use compile.internal.mir.dump_ownership_analysis_input_from_mir
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
    stmt0_args := string[]()
    stmt0_args = append(stmt0_args, "stmt0")
    stmt1_args := string[]()
    stmt1_args = append(stmt1_args, "stmt1")
    then_args := string[]()
    then_args = append(then_args, "then")
    else_args := string[]()
    else_args = append(else_args, "else")
    entry_statements := mir_statement[]()
    entry_statements.push(mir_statement::eval(mir_eval_stmt { op: "line", args stmt0_args }))
    entry_statements.push(mir_statement::eval(mir_eval_stmt { op: "line", args stmt1_args }))
    then_statements := mir_statement[]()
    then_statements.push(mir_statement::eval(mir_eval_stmt { op: "line", args then_args }))
    else_statements := mir_statement[]()
    else_statements.push(mir_statement::eval(mir_eval_stmt { op: "line", args else_args }))
    entry_edges := mir_control_edge[]()
    entry_edges = append(entry_edges, mir_control_edge { label: "then", target 1, args mir_operand[]() })
    entry_edges = append(entry_edges, mir_control_edge { label: "else", target 2, args mir_operand[]() })
    then_edges := mir_control_edge[]()
    then_edges = append(then_edges, mir_control_edge { label: "merge", target 3, args mir_operand[]() })
    else_edges := mir_control_edge[]()
    else_edges = append(else_edges, mir_control_edge { label: "merge", target 3, args mir_operand[]() })
    diamond_blocks := mir_basic_block[]()
    diamond_blocks.push(mir_basic_block {
        id: 0,
        label: "entry", statements entry_statements, terminator mir_terminator {
            kind: "branch", edges entry_edges,
        },
    })
    diamond_blocks.push(mir_basic_block {
        id: 1,
        label: "then", statements then_statements, terminator mir_terminator {
            kind: "jump", edges then_edges,
        },
    })
    diamond_blocks.push(mir_basic_block {
        id: 2,
        label: "else", statements else_statements, terminator mir_terminator {
            kind: "jump", edges else_edges,
        },
    })
    diamond_blocks.push(mir_basic_block {
        id: 3,
        label: "merge", statements mir_statement[](), terminator mir_terminator {
            kind: "return", edges mir_control_edge[](),
        },
    })
    diamond := mir_graph {
        function_name: "diamond", blocks diamond_blocks, locals mir_local_slot[](), string trace[](), entry 0, exit 3,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
    point_map := build_mir_point_map(diamond)
    if mir_point_count(diamond) != 8 {
        return 1
    }
    if len(point_map.points) != mir_point_count(diamond) {
        return 1
    }
    if mir_point_text(diamond, point_map.points[0]) != "BB0(entry):stmt0" { return 1 }
    if mir_point_text(diamond, point_map.points[1]) != "BB0(entry):stmt1" { return 1 }
    if mir_point_text(diamond, point_map.points[2]) != "BB0(entry):term" { return 1 }
    if mir_point_text(diamond, point_map.points[3]) != "BB1(then):stmt0" { return 1 }
    if mir_point_text(diamond, point_map.points[4]) != "BB1(then):term" { return 1 }
    if mir_point_text(diamond, point_map.points[5]) != "BB2(else):stmt0" { return 1 }
    if mir_point_text(diamond, point_map.points[6]) != "BB2(else):term" { return 1 }
    if mir_point_text(diamond, point_map.points[7]) != "BB3(merge):term" { return 1 }
    if mir_point_id(point_map, 0, 2) != 2 { return 1 }
    if mir_point_id(point_map, 1, 1) != 4 { return 1 }
    if mir_point_id(point_map, 3, 0) != 7 { return 1 }
    fact_statements := mir_statement[]()
    fact_statements.push(mir_statement::borrow(mir_borrow_stmt {
        ref_name: "_2", place mir_place { root: "_1", projections: mir_place_projection[]() }, mutable false,
    }))
    fact_statements.push(mir_statement::ref_assign(mir_ref_assign_stmt {
        target_ref: "_3", source_ref "_2",
    }))
    fact_statements.push(mir_statement::ref_use(mir_ref_use_stmt {
        ref_name: "_3",
    }))
    fact_blocks := mir_basic_block[]()
    fact_blocks.push(mir_basic_block {
        id: 0,
        label: "entry", statements fact_statements, terminator mir_terminator {
            kind: "return", edges mir_control_edge[](),
        },
    })
    fact_graph := mir_graph {
        function_name: "facts", blocks fact_blocks, locals mir_local_slot[](), string trace[](), entry 0, exit 0,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
    expected_facts := "PointCount = 4 | Ref(_2) = R0 | Ref(_3) = R1 | Loan0 issued = {P0} place=_1 | RefLoan(R0) = L0 | RefLoan(R1) = L0 | Outlives(R0,R1) | RegionPoint(R0) = {P0} | RegionPoint(R1) = {P2}"
    if dump_ownership_analysis_input_from_mir(fact_graph) != expected_facts {
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
