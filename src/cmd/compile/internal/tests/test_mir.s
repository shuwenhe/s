package compile.internal.tests.test_mir
import (
    "compile.internal.mir"
    "compile.internal.syntax"
    "compile.internal.ir.lower"
    "std.slices"
    "std.io"
)

func mir_point_count(mir_graph graph) int {
    return mir.mir_point_count(graph)
}

func run_mir_suite() int {
    if mir.trace_branch("flag", "then", "else") != "branch flag |   then then |   else else" {
        return 1
    }
    if mir.trace_loop("while", "cond", "body") != "while cond |   body body" {
        return 1
    }
    if mir.trace_switch("value", "arms") != "switch value | arms" {
        return 1
    }
    if mir.trace_switch("value", "") != "switch value" {
        return 1
    }
    blocks := mir_basic_block[]()
    blocks.push(mir_basic_block {
        id: 0,
        label: "entry", statements mir_statement[](), terminator mir_terminator {
            kind: "return", condition: option.none, edges mir_control_edge[](),
        },
    })
    graph := mir_graph {
        function_name: "main", blocks blocks, locals mir_local_slot[](), string trace[](), entry 0, exit 0,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
    if mir.block_count(graph) != 1 {
        return 1
    }
    if mir.dump_graph(graph) != "mir main blocks=1 entry=0 exit=0 | bb0(entry) stmts=0 term=return" {
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
            kind: "return", condition: option.none, edges mir_control_edge[](),
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
    branch_condition := option.some(mir_operand {
        kind: "local", value: "cond", type_name: "bool",
    })
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
            kind: "branch", condition: branch_condition, edges entry_edges,
        },
    })
    diamond_blocks.push(mir_basic_block {
        id: 1,
        label: "then", statements then_statements, terminator mir_terminator {
            kind: "jump", condition: option.none, edges then_edges,
        },
    })
    diamond_blocks.push(mir_basic_block {
        id: 2,
        label: "else", statements else_statements, terminator mir_terminator {
            kind: "jump", condition: option.none, edges else_edges,
        },
    })
    diamond_blocks.push(mir_basic_block {
        id: 3,
        label: "merge", statements mir_statement[](), terminator mir_terminator {
            kind: "return", condition: option.none, edges mir_control_edge[](),
        },
    })
    diamond := mir_graph {
        function_name: "diamond", blocks diamond_blocks, locals mir_local_slot[](), string trace[](), entry 0, exit 3,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
    point_map := mir.build_mir_point_map(diamond)
    if mir_point_count(diamond) != 8 {
        return 1
    }
    if len(point_map.points) != mir_point_count(diamond) {
        return 1
    }
    if mir.mir_point_text(diamond, point_map.points[0]) != "BB0(entry):stmt0" { return 1 }
    if mir.mir_point_text(diamond, point_map.points[1]) != "BB0(entry):stmt1" { return 1 }
    if diamond.blocks[0].terminator.condition.is_none() { return 1 }
    if diamond.blocks[0].terminator.condition.unwrap().value != "cond" { return 1 }
    if mir.mir_point_text(diamond, point_map.points[2]) != "BB0(entry):term" { return 1 }
    if mir.mir_point_text(diamond, point_map.points[3]) != "BB1(then):stmt0" { return 1 }
    if mir.mir_point_text(diamond, point_map.points[4]) != "BB1(then):term" { return 1 }
    if mir.mir_point_text(diamond, point_map.points[5]) != "BB2(else):stmt0" { return 1 }
    if mir.mir_point_text(diamond, point_map.points[6]) != "BB2(else):term" { return 1 }
    if mir.mir_point_text(diamond, point_map.points[7]) != "BB3(merge):term" { return 1 }
    if mir.mir_point_id(point_map, 0, 2) != 2 { return 1 }
    if mir.mir_point_id(point_map, 1, 1) != 4 { return 1 }
    if mir.mir_point_id(point_map, 3, 0) != 7 { return 1 }
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
            kind: "return", condition: option.none, edges mir_control_edge[](),
        },
    })
    fact_graph := mir_graph {
        function_name: "facts", blocks fact_blocks, locals mir_local_slot[](), string trace[](), entry 0, exit 0,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
    expected_facts := "PointCount = 4 | Ref(_2) = R0 | Ref(_3) = R1 | Loan0 issued = {P0} place=_1 | RefLoan(R0) = L0 | RefLoan(R1) = L0 | Outlives(R0,R1) | RegionPoint(R0) = {P0} | RegionPoint(R1) = {P2}"
    if mir.dump_ownership_analysis_input_from_mir(fact_graph) != expected_facts {
        return 1
    }
    expected_shadow := "RealMIROwnershipShadow\nRealMIRFacts(point_count=4, refs=2, loans=1, outlives=1)\nLoanLivePoints(L0) = {P0,P2}\nSharedSolverShadow(iterations=2, converged=true)\n"
    if mir.dump_ownership_shadow_from_mir(fact_graph) != expected_shadow {
        return 1
    }
    if test_real_mir_source_ownership_facts() != 0 {
        return 1
    }
    if test_real_mir_semantic_order() != 0 {
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

func test_real_mir_source_ownership_facts() int {
    // Real S source fixture testing with actual frontend and lowering pipeline
    // Fixture: real_mir_ref_flow.s
    // Semantics: borrow + ref_assign + ref_use
    // Verification: Statement order preservation through canonical points
    
    fixture_path := "src/cmd/compile/internal/tests/fixtures/real_mir_ref_flow.s"
    
    // Read and parse real source
    source_result := syntax.read_source(fixture_path)
    if source_result.is_err() {
        return 1
    }
    source := source_result.unwrap()
    
    parsed, parse_err := syntax.parse_source(source)
    if parse_err.message != "" {
        return 1
    }
    
    // Lower to real MIR with ownership semantics
    mir_result := lower.lower_main_to_mir(parsed)
    if mir_result.is_err() {
        return 1
    }
    graph := mir_result.unwrap()
    
    // Build canonical point map
    point_map := mir.build_mir_point_map(graph)
    if len(point_map.points) == 0 {
        return 1
    }
    
    // Extract ownership facts from real MIR
    facts := mir.build_ownership_facts_from_mir(graph, point_map)
    
    // Verify facts structure exists
    if facts.input.point_count == 0 {
        return 1
    }
    
    // Verify all three ownership statement types are present
    // (borrow, ref_assign, ref_use)
    has_borrow := false
    has_ref_assign := false
    has_ref_use := false
    
    i := 0
    while i < len(graph.blocks) {
        j := 0
        while j < len(graph.blocks[i].statements) {
            switch graph.blocks[i].statements[j] {
                mir_statement::borrow(_) : has_borrow = true
                mir_statement::ref_assign(_) : has_ref_assign = true
                mir_statement::ref_use(_) : has_ref_use = true
                _ : { }
            }
            j = j + 1
        }
        i = i + 1
    }
    
    if !has_borrow || !has_ref_assign || !has_ref_use {
        return 1
    }
    
    // Verify facts dump format contains expected keys (no solver output)
    facts_dump := mir.dump_ownership_analysis_input_from_mir(graph)
    if facts_dump == "" {
        return 1
    }
    
    // Facts should contain extraction markers, not solver results
    // Required: PointCount, Ref, Loan, RefLoan, Outlives, RegionPoint
    // Forbidden: LoanLivePoints (solver output), converged (solver output), iterations
    if !contains_substring(facts_dump, "PointCount") {
        return 1
    }
    if !contains_substring(facts_dump, "Ref") {
        return 1
    }
    if contains_substring(facts_dump, "LoanLivePoints") {
        return 1
    }
    if contains_substring(facts_dump, "converged") {
        return 1
    }
    
    0
}

func contains_substring(string haystack, string needle) bool {
    i := 0
    while i <= len(haystack) - len(needle) {
        j := 0
        matched := true
        while j < len(needle) {
            if haystack[i + j] != needle[j] {
                matched = false
                break
            }
            j = j + 1
        }
        if matched {
            return true
        }
        i = i + 1
    }
    false
}

func test_real_mir_semantic_order() int {
    // Step 6c: Verify semantic point ordering with interleaved statements
    // Ensures ownership operations maintain source-order semantics
    // even when mixed with regular (non-ownership) statements
    
    fixture_path := "src/cmd/compile/internal/tests/fixtures/real_mir_ref_flow.s"
    
    // Read and lower real source
    source_result := syntax.read_source(fixture_path)
    if source_result.is_err() {
        return 1
    }
    source := source_result.unwrap()
    
    parsed, parse_err := syntax.parse_source(source)
    if parse_err.message != "" {
        return 1
    }
    
    mir_result := lower.lower_main_to_mir(parsed)
    if mir_result.is_err() {
        return 1
    }
    graph := mir_result.unwrap()
    
    // Build point map for canonical ID mapping
    point_map := mir.build_mir_point_map(graph)
    if len(point_map.points) == 0 {
        return 1
    }
    
    // Find ownership statements and their positions
    borrow_block := -1
    borrow_stmt := -1
    ref_assign_block := -1
    ref_assign_stmt := -1
    ref_use_block := -1
    ref_use_stmt := -1
    
    block_idx := 0
    while block_idx < len(graph.blocks) {
        stmt_idx := 0
        while stmt_idx < len(graph.blocks[block_idx].statements) {
            switch graph.blocks[block_idx].statements[stmt_idx] {
                mir_statement::borrow(_) : {
                    borrow_block = block_idx
                    borrow_stmt = stmt_idx
                }
                mir_statement::ref_assign(_) : {
                    ref_assign_block = block_idx
                    ref_assign_stmt = stmt_idx
                }
                mir_statement::ref_use(_) : {
                    ref_use_block = block_idx
                    ref_use_stmt = stmt_idx
                }
                _ : { }
            }
            stmt_idx = stmt_idx + 1
        }
        block_idx = block_idx + 1
    }
    
    // Verify all three statements found
    if borrow_block == -1 || ref_assign_block == -1 || ref_use_block == -1 {
        return 1
    }
    
    // Verify same basic block (for now, Step 6c phase 1)
    if borrow_block != ref_assign_block || ref_assign_block != ref_use_block {
        return 1
    }
    
    // Verify semantic order within block (relative point ordering)
    // NOT checking absolute P0/P1/P2, only relative sequence
    if !(borrow_stmt < ref_assign_stmt && ref_assign_stmt < ref_use_stmt) {
        return 1
    }
    
    // Additional: Verify points exist and are in order too
    borrow_point := mir.mir_point_id(point_map, graph.blocks[borrow_block].id, borrow_stmt)
    ref_assign_point := mir.mir_point_id(point_map, graph.blocks[ref_assign_block].id, ref_assign_stmt)
    ref_use_point := mir.mir_point_id(point_map, graph.blocks[ref_use_block].id, ref_use_stmt)
    
    // Same-block canonical ordering should match statement ordering
    if !(borrow_point < ref_assign_point && ref_assign_point < ref_use_point) {
        return 1
    }
    
    0
}
