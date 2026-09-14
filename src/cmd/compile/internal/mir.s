package compile.internal.mir
import (
    "compile.internal.borrow"
    "compile.internal.ownership.analysis"
    "compile.internal.typesys"
    "s"
    "std"
    "std.option"
    "std.prelude"
)
// C.3.1b.2-pre.A1: Canonical projection kind
// Structured representation of place projection operations
enum mir_projection_kind {
    field   // struct/tuple field access (value: field name or index)
    deref   // pointer dereference (value: unused)
    index   // array/slice indexing (value: index expression)
}
struct mir_operand {
    string kind
    string value
    string type_name
}
struct mir_place_projection {
    mir_projection_kind kind   // Canonical: enum, not string
    string value               // Field name or index expression (string for now)
}
struct mir_place {
    string root
    mir_place_projection[] projections
}
struct mir_flow_state {
    string[] moved
    string[] dropped
    string[] shared_borrows
    string[] mutable_borrows
}
struct mir_local_slot {
    int id
    string name
    string kind
    int version
    string type_name
    bool copyable
}
struct mir_assign_stmt {
    int target
    string op
    string[] args
}
struct mir_eval_stmt {
    string op
    string[] args
}
struct mir_move_stmt {
    int target
    source mir_operand
}
struct mir_copy_stmt {
    int target
    source mir_operand
}
struct mir_drop_stmt {
    int slot
}
struct mir_borrow_stmt {
    string ref_name
    mir_place place
    bool mutable
}
struct mir_ref_use_stmt {
    string ref_name
}
struct mir_ref_assign_stmt {
    string target_ref
    string source_ref
}
enum mir_statement {
    assign(mir_assign_stmt),
    eval(mir_eval_stmt),
    move(mir_move_stmt),
    copy(mir_copy_stmt),
    drop(mir_drop_stmt),
    borrow(mir_borrow_stmt),
    ref_use(mir_ref_use_stmt),
    ref_assign(mir_ref_assign_stmt),
}
struct mir_control_edge {
    string label
    int target
    mir_operand[] args
}
struct mir_terminator {
    string kind
    mir_control_edge[] edges
}
struct mir_basic_block {
    int id
    string label
    mir_statement[] statements
    terminator mir_terminator
}
struct mir_graph {
    string function_name
    mir_basic_block[] blocks
    mir_local_slot[] locals
    string[] trace
    int entry
    int exit
    bool borrow_ok
    int borrow_errors
    string borrow_message
}
struct mir_point {
    int block_id
    int statement_index
}
struct mir_point_map {
    mir_point[] points
}
// B1.2: Preserve canonical borrowed Place through MIR ownership facts
// Dual-path migration: legacy string paths + canonical structured places
// 
// LOAN IDENTITY INVARIANT (B1.3)
// All loan-indexed metadata must share the same dense Loan ID:
//   For Loan L:
//     input.loan_points[L]          → issued_at points
//     input.loan_count              → total loan count (determines L validity)
//     loan_places[L]                → legacy string (diagnostic)
//     loan_borrowed_places[L]       → canonical mir_place
// 
// Maintenance rule: every Borrow statement that increments loan_count
// must ALSO append to BOTH loan_places and loan_borrowed_places.
// Violation results in L+1 being out-of-sync with all future loans.
struct mir_ownership_facts {
    ownership_analysis_input input
    string[] ref_names
    // LEGACY / DEBUG: string representation of borrowed places
    // Used for backward compatibility and diagnostic output only
    // Authority: NONE (use loan_borrowed_places for semantics)
    // TODO: Remove after legacy diagnostic consumers migrate.
    string[] loan_places
    // CANONICAL / SEMANTIC: structured representation of borrowed places
    // Indexed by loan_id, stored directly from mir_borrow_stmt.place
    // Structured preservation: no string serialization involved
    // Authority: YES (source of truth for place identity)
    // Contract: loan_borrowed_places[i] corresponds to loan id i (see LOAN IDENTITY INVARIANT above)
    mir_place[] loan_borrowed_places
}
func build_mir_point_map(mir_graph graph) mir_point_map {
    points := mir_point[]()
    emitted_blocks := 0
    next_block_id := 0
    // Deterministic dense ids: block_id ascending, then statements, then terminator.
    for emitted_blocks < len(graph.blocks) {
        block_index := -1
        scan := 0
        for scan < len(graph.blocks) {
            if graph.blocks[scan].id == next_block_id {
                block_index = scan
            }
            scan = scan + 1
        }
        if block_index >= 0 {
            stmt_index := 0
            for stmt_index < len(graph.blocks[block_index].statements) {
                points = append(points, mir_point { block_id: graph.blocks[block_index].id, statement_index stmt_index })
                stmt_index = stmt_index + 1
            }
            points = append(points, mir_point { block_id: graph.blocks[block_index].id, statement_index len(graph.blocks[block_index].statements) })
            emitted_blocks = emitted_blocks + 1
        }
        next_block_id = next_block_id + 1
    }
    mir_point_map { points: points }
}
func mir_point_id(mir_point_map point_map, int block_id, int statement_index) int {
    i := 0
    for i < len(point_map.points) {
        if point_map.points[i].block_id == block_id && point_map.points[i].statement_index == statement_index {
            return i
        }
        i = i + 1
    }
    -1
}
func mir_point_count(mir_graph graph) int {
    count := 0
    i := 0
    for i < len(graph.blocks) {
        count = count + len(graph.blocks[i].statements) + 1
        i = i + 1
    }
    count
}
func mir_point_text(mir_graph graph, mir_point point) string {
    label := "unknown"
    i := 0
    for i < len(graph.blocks) {
        if graph.blocks[i].id == point.block_id {
            label = graph.blocks[i].label
            if point.statement_index == len(graph.blocks[i].statements) {
                return "BB" + std.prelude.to_string(point.block_id) + "(" + label + "):term"
            }
        }
        i = i + 1
    }
    "BB" + std.prelude.to_string(point.block_id) + "(" + label + "):stmt" + std.prelude.to_string(point.statement_index)
}
func build_ownership_facts_from_mir(mir_graph graph, mir_point_map points) mir_ownership_facts {
    facts := mir_empty_ownership_facts(len(points.points))
    block_index := 0
    for block_index < len(graph.blocks) {
        stmt_index := 0
        for stmt_index < len(graph.blocks[block_index].statements) {
            point := mir_point_id(points, graph.blocks[block_index].id, stmt_index)
            switch graph.blocks[block_index].statements[stmt_index] {
                mir_statement::borrow(borrow_stmt) : {
                    ref_id := mir_ownership_ref_id(&facts, borrow_stmt.ref_name)
                    loan_id := facts.input.loan_count
                    facts.input.loan_count = facts.input.loan_count + 1
                    facts.input.loan_points = append(facts.input.loan_points, mir_add_point_value(0, point))
                    // [LEGACY] Store string representation for backward compatibility/diagnostics
                    facts.loan_places = append(facts.loan_places, mir_place_key(borrow_stmt.place))
                    // [CANONICAL] Store structured place directly from borrow statement
                    // Structural preservation without string conversion (no serialization round-trip)
                    // This is the canonical semantic record of what place was borrowed
                    facts.loan_borrowed_places = append(facts.loan_borrowed_places, borrow_stmt.place)
                    facts.input.ref_loans[ref_id] = loan_id
                    facts.input.region_points[ref_id] = mir_add_point_value(facts.input.region_points[ref_id], point)
                }
                mir_statement::ref_use(use_stmt) : {
                    ref_id := mir_ownership_ref_id(&facts, use_stmt.ref_name)
                    facts.input.region_points[ref_id] = mir_add_point_value(facts.input.region_points[ref_id], point)
                }
                mir_statement::ref_assign(assign_stmt) : {
                    target_ref := mir_ownership_ref_id(&facts, assign_stmt.target_ref)
                    source_ref := mir_ownership_ref_id(&facts, assign_stmt.source_ref)
                    facts.input.ref_loans[target_ref] = facts.input.ref_loans[source_ref]
                    facts.input.outlives_from = append(facts.input.outlives_from, source_ref)
                    facts.input.outlives_to = append(facts.input.outlives_to, target_ref)
                    facts.input.outlives_count = facts.input.outlives_count + 1
                }
                _ : { }
            }
            stmt_index = stmt_index + 1
        }
        block_index = block_index + 1
    }
    facts
}
func build_ownership_analysis_input_from_mir(mir_graph graph, mir_point_map points) ownership_analysis_input {
    build_ownership_facts_from_mir(graph, points).input
}
func mir_empty_ownership_facts(int point_count) mir_ownership_facts {
    mir_ownership_facts {
        input: ownership_analysis_input {
            point_count: point_count, ref_seen int[](), ref_loans int[](), region_points int[](), loan_points int[](), outlives_from int[](), outlives_to int[](), outlives_count 0, loan_count 0,
        },
        ref_names: string[](),
        loan_places: string[](),
        loan_borrowed_places: mir_place[](),
    }
}
// B1.3: Query Loan's borrowed Place (shadow analysis entry point)
// Returns the canonical mir_place that Loan with given id borrowed.
// 
// Preconditions:
//   - facts must not be nil
//   - loan_id must be in [0, facts.input.loan_count)
// 
// Returns:
//   place: the mir_place structure representing the borrowed location
//   ok: true if loan_id is valid, false if out-of-bounds
// 
// Contract: caller MUST check bool ok; must NOT use place.root == "" as sentinel.
// Failure produces zero-value place + false; success produces place + true.
// 
// Example usage:
//   place, ok := mir_loan_borrowed_place(&facts, 0)
//   if !ok {
//       // loan_id out of bounds
//   } else {
//       // process place
//   }
func mir_loan_borrowed_place(mir_ownership_facts* facts, int loan_id) (mir_place, bool) {
    // Precondition: facts must not be nil
    if facts == nil {
        return mir_place{}, false
    }
    // Bounds check: loan_id must be in [0, loan_count)
    if loan_id < 0 || loan_id >= facts.input.loan_count {
        return mir_place{}, false
    }
    // Invariant check: ensure array is in sync with loan_count
    if loan_id >= len(facts.loan_borrowed_places) {
        return mir_place{}, false
    }
    // Return the canonical structured place for this loan
    return facts.loan_borrowed_places[loan_id], true
}
// Helper: Create a mir_place from root and field names (for testing)
func mir_place_from_fields(string root, string[] fields) mir_place {
    projections := mir_place_projection[]()
    i := 0
    for i < len(fields) {
        projections = append(projections, mir_place_projection{
            kind: mir_projection_kind::field,
            value: fields[i],
        })
        i = i + 1
    }
    mir_place{
        root: root,
        projections: projections,
    }
}
func mir_ownership_ref_id(mir_ownership_facts* facts, string name) int {
    i := 0
    for i < len(facts.ref_names) {
        if facts.ref_names[i] == name { return i }
        i = i + 1
    }
    facts.ref_names = append(facts.ref_names, name)
    facts.input.ref_seen = append(facts.input.ref_seen, 1)
    facts.input.ref_loans = append(facts.input.ref_loans, -1)
    facts.input.region_points = append(facts.input.region_points, 0)
    len(facts.ref_names) - 1
}
func mir_add_point_value(int bits, int point) int {
    if point < 0 { return bits }
    bit := 1
    i := 0
    for i < point {
        bit = bit * 2
        i = i + 1
    }
    if mir_point_bit_set(bits, bit) { return bits }
    bits + bit
}
func mir_point_bit_set(int bits, int bit) bool {
    value := bits / bit
    return value % 2 == 1
}
func mir_points_string(int bits) string {
    out := "{"
    first := true
    point := 0
    bit := 1
    for point < 31 {
        if mir_point_bit_set(bits, bit) {
            if !first { out = out + "," }
            out = out + "P" + std.prelude.to_string(point)
            first = false
        }
        point = point + 1
        bit = bit * 2
    }
    out + "}"
}
func dump_ownership_analysis_input_from_mir(mir_graph graph) string {
    points := build_mir_point_map(graph)
    facts := build_ownership_facts_from_mir(graph, points)
    input := facts.input
    out := "PointCount = " + std.prelude.to_string(input.point_count)
    i := 0
    for i < len(facts.ref_names) {
        out = out + " | Ref(" + facts.ref_names[i] + ") = R" + std.prelude.to_string(i)
        i = i + 1
    }
    i = 0
    for i < input.loan_count {
        out = out + " | Loan" + std.prelude.to_string(i) + " issued = " + mir_points_string(input.loan_points[i])
        out = out + " place=" + facts.loan_places[i]
        i = i + 1
    }
    i = 0
    for i < len(facts.ref_names) {
        if input.ref_loans[i] >= 0 {
            out = out + " | RefLoan(R" + std.prelude.to_string(i) + ") = L" + std.prelude.to_string(input.ref_loans[i])
        }
        i = i + 1
    }
    i = 0
    for i < input.outlives_count {
        out = out + " | Outlives(R" + std.prelude.to_string(input.outlives_from[i]) + ",R" + std.prelude.to_string(input.outlives_to[i]) + ")"
        i = i + 1
    }
    i = 0
    for i < len(facts.ref_names) {
        out = out + " | RegionPoint(R" + std.prelude.to_string(i) + ") = " + mir_points_string(input.region_points[i])
        i = i + 1
    }
    out
}
func dump_ownership_shadow_from_mir(mir_graph graph) string {
    points := build_mir_point_map(graph)
    facts := build_ownership_facts_from_mir(graph, points)
    analysis := compile.internal.ownership.analysis.analyze_ownership_liveness(facts.input)
    out := "RealMIROwnershipShadow\n"
    out = out + "RealMIRFacts(point_count=" + std.prelude.to_string(facts.input.point_count) + ", refs=" + std.prelude.to_string(len(facts.ref_names)) + ", loans=" + std.prelude.to_string(facts.input.loan_count) + ", outlives=" + std.prelude.to_string(facts.input.outlives_count) + ")\n"
    i := 0
    for i < facts.input.loan_count {
        out = out + "LoanLivePoints(L" + std.prelude.to_string(i) + ") = " + mir_points_string(analysis.loan_live_points[i]) + "\n"
        i = i + 1
    }
    out = out + "SharedSolverShadow(iterations=" + std.prelude.to_string(analysis.iterations) + ", converged=true)\n"
    out
}
func lower_function_graph(function_decl function) mir_graph {
    if function.body.is_some() {
        return lower_block_graph(function.sig.name, function.sig.params, function.body.unwrap())
    }
    empty_statements := mir_statement[]()
    empty_edges := mir_control_edge[]()
    blocks := mir_basic_block[]()
    blocks.push(mir_basic_block {
        id: 0,
        label: "entry", statements empty_statements, terminator mir_terminator {
            kind: "return", edges empty_edges,
        },
    })
    trace := string[]()
    trace = append(trace, "block |   yield unit")
    mir_graph {
        function_name: function.sig.name, blocks blocks, locals mir_local_slot[](), trace trace, entry 0, exit 0,
        borrow_ok: true, borrow_errors: 0, borrow_message: "",
    }
}
func lower_block_graph(string function_name, param[] params, block_expr block) mir_graph {
    locals := mir_collect_locals(params, block)
    statements := mir_statement[]()
    events := string[]()
    local_index := 0
    for local_index < len(locals) {
        events = append(events, "declare:" + locals[local_index].name)
        local_index = local_index + 1
    }
    index := 0
    for index < len(block.statements) {
        stmt_text := join_text(s.dump_stmt(block.statements[index], indent(1)), " | ")
        args := string[]()
        args = append(args, stmt_text)
        statements.push(mir_statement::eval(mir_eval_stmt {
            op: "stmt", args args,
        }))
        mir_append_ownership_semantics_from_stmt(statements, block.statements[index])
        events = mir_extend_events(events, mir_stmt_events(block.statements[index], locals))
        index = index + 1
    }
    if block.final_expr.is_some() {
        events = mir_extend_events(events, mir_expr_events(block.final_expr.unwrap(), locals, true))
        mir_append_ownership_semantics_from_expr(statements, block.final_expr.unwrap(), "")
    }
    mir_append_scope_drops(locals, statements, events)
    borrow_result := compile.internal.borrow.borrow_check_events(events)
    trace := string[]()
    trace_text := "block"
    index = 0
    for index < len(block.statements) {
        stmt_trace := join_text(s.dump_stmt(block.statements[index], indent(1)), " | ")
        trace_text = trace_text + " | " + indent(1) + stmt_trace
        index = index + 1
    }
    if block.final_expr.is_some() {
        trace_text = trace_text + " | " + indent(1) + "yield " + s.dump_expr(block.final_expr.unwrap())
    } else {
        trace_text = trace_text + " | " + indent(1) + "yield unit"
    }
    trace = append(trace, trace_text)
    blocks := mir_basic_block[]()
    blocks.push(mir_basic_block {
        id: 0,
        label: "entry", statements statements, terminator mir_terminator {
            kind: "return", edges mir_control_edge[](),
        },
    })
    mir_graph {
        function_name: function_name, blocks blocks, locals locals, trace trace, entry 0, exit 0,
        borrow_ok: borrow_result.ok, borrow_errors: borrow_result.errors, borrow_message: borrow_result.message,
    }
}
func mir_find_local(mir_local_slot[] locals, string name) int {
    i := 0
    for i < len(locals) {
        if locals[i].name == name { return i }
        i = i + 1
    }
    -1
}
func mir_type_is_copy(string type_name) bool {
    compile.internal.typesys.is_copy_type(type_name)
}
func mir_append_scope_drops(mir_local_slot[] locals, mir_statement[] statements, string[] events) () {
    i := len(locals) - 1
    for i >= 0 {
        if compile.internal.typesys.requires_drop(locals[i].type_name) && locals[i].type_name != "unknown" && !mir_local_moved_at_exit(locals[i].name, events) {
            statements.push(mir_statement::drop(mir_drop_stmt { slot: locals[i].id }))
        }
        i = i - 1
    }
}
func mir_local_moved_at_exit(string name, string[] events) bool {
    state := mir_flow_state { moved: string[](), dropped: string[](), shared_borrows: string[](), mutable_borrows: string[]() }
    i := 0
    for i < len(events) {
        state = mir_apply_flow_event(state, events[i])
        i = i + 1
    }
    mir_contains(state.moved, name)
}
func mir_contains(string[] values, string value) bool {
    i := 0
    for i < len(values) {
        if values[i] == value { return true }
        i = i + 1
    }
    false
}
func mir_remove(string[] values, string value) string[] {
    out := string[]()
    i := 0
    for i < len(values) {
        if values[i] != value { out = append(out, values[i]) }
        i = i + 1
    }
    out
}
func mir_add_unique(string[] values, string value) string[] {
    if value == "" || mir_contains(values, value) { return values }
    values = append(values, value)
    values
}
func mir_apply_flow_event(mir_flow_state state, string event) mir_flow_state {
    if starts_with(event, "move:") {
        name := slice(event, 5, len(event))
        state.moved = mir_add_unique(state.moved, name)
        state.dropped = mir_remove(state.dropped, name)
    } else if starts_with(event, "write:") {
        name := slice(event, 6, len(event))
        state.moved = mir_remove(state.moved, name)
        state.dropped = mir_remove(state.dropped, name)
    } else if starts_with(event, "drop:") {
        name := slice(event, 5, len(event))
        state.dropped = mir_add_unique(state.dropped, name)
        state.moved = mir_remove(state.moved, name)
    } else if starts_with(event, "shared:") {
        state.shared_borrows = mir_add_unique(state.shared_borrows, slice(event, 7, len(event)))
    } else if starts_with(event, "mutable:") {
        state.mutable_borrows = mir_add_unique(state.mutable_borrows, slice(event, 8, len(event)))
    }
    state
}
func mir_place_from_expr(expr value) mir_place {
    switch value {
        expr.name(name_expr) : {
            return mir_place { root: name_expr.name, projections: mir_place_projection[]() }
        }
        expr.member(member_expr) : {
            place := mir_place_from_expr(member_expr.target.unwrap())
            place.projections = append(place.projections, mir_place_projection { kind: mir_projection_kind.field, value: member_expr.member })
            return place
        }
        expr.index(index_expr) : {
            place := mir_place_from_expr(index_expr.target.unwrap())
            place.projections = append(place.projections, mir_place_projection { kind: mir_projection_kind.index, value: s.dump_expr(index_expr.index.unwrap()) })
            return place
        }
        _ : { return mir_place { root: "", projections: mir_place_projection[]() } }
    }
}
func mir_place_key(mir_place place) string {
    if place.root == "" { return "" }
    out := place.root
    i := 0
    for i < len(place.projections) {
        projection := place.projections[i]
        // C.3.1b.2-pre.A1: Canonical projection kind enum dispatch
        // mir_place_key() is diagnostic/lookup helper, NOT ownership semantic authority
        switch projection.kind {
            mir_projection_kind.field : { out = out + "." + projection.value }
            mir_projection_kind.index : { out = out + "[" + projection.value + "]" }
            mir_projection_kind.deref : { out = out + ".*" }
        }
        i = i + 1
    }
    out
}
// C.3.1b.2-pre.A3: Structural equality for MIR places
// Compares two places for identity equality
// This is MIR Place identity equality, NOT alias equivalence
// Two places are equal if and only if:
//   1. roots are identical
//   2. projection counts are identical
//   3. each projection kind and value are identical
// NOTE: Uses direct field comparison, NOT mir_place_key() or string parsing
func mir_place_equal(a mir_place, b mir_place) bool {
    // [1] Root identity must match
    if a.root != b.root {
        return false
    }
    // [2] Projection count must match
    if len(a.projections) != len(b.projections) {
        return false
    }
    // [3] Each projection must match (kind and value)
    i := 0
    for i < len(a.projections) {
        // Kind must match (enum-based comparison, never string dispatch)
        if a.projections[i].kind != b.projections[i].kind {
            return false
        }
        // Value must match (direct string comparison on stored value)
        if a.projections[i].value != b.projections[i].value {
            return false
        }
        i = i + 1
    }
    // All fields match: places are equal
    return true
}
// C.3.1b.2-pre.A4: Structural prefix for MIR places
// Determines if prefix is a prefix of place (including exact match)
// Algebraic basis for place overlap: places overlap iff they share a common prefix
// Examples:
//   prefix(Local(1), Local(1))         → true   (exact match)
//   prefix(Local(1), Local(1).Field(0)) → true   (proper prefix)
//   prefix(Local(1).Field(0), Local(1).Field(0).Field(1)) → true (nested)
//   prefix(Local(1).Field(0), Local(1).Field(1)) → false (different branch)
//   prefix(Local(1), Local(2))         → false (different root)
func mir_place_is_prefix(prefix mir_place, place mir_place) bool {
    // [1] Roots must match (necessary for any prefix relationship)
    if prefix.root != place.root {
        return false
    }
    // [2] Prefix projection count must not exceed place count
    if len(prefix.projections) > len(place.projections) {
        return false
    }
    // [3] Each prefix projection must match corresponding place projection
    i := 0
    for i < len(prefix.projections) {
        // Kind must match exactly
        if prefix.projections[i].kind != place.projections[i].kind {
            return false
        }
        // Value must match exactly
        if prefix.projections[i].value != place.projections[i].value {
            return false
        }
        i = i + 1
    }
    // Prefix is a valid prefix of place
    return true
}
func mir_extend_events(string[] base, string[] extra) string[] {
    i := 0
    for i < len(extra) {
        base = append(base, extra[i])
        i = i + 1
    }
    base
}
func mir_collect_locals(param[] params, block_expr block) mir_local_slot[] {
    locals := mir_local_slot[]()
    i := 0
    for i < len(params) {
        locals = append(locals, mir_local_slot { id: len(locals), name: params[i].name, kind: "param", version: 0, type_name: params[i].type_name, copyable: mir_type_is_copy(params[i].type_name) })
        i = i + 1
    }
    i = 0
    for i < len(block.statements) {
        switch block.statements[i] {
            stmt.let(let_stmt) : {
                if mir_find_local(locals, let_stmt.name) < 0 {
                    type_name := mir_expr_type_name(let_stmt.value)
                    if let_stmt.type_name.is_some() { type_name = let_stmt.type_name.unwrap() }
                    locals = append(locals, mir_local_slot { id: len(locals), name: let_stmt.name, kind: "local", version: 0, type_name: type_name, copyable: mir_type_is_copy(type_name) })
                }
            }
            _ : { }
        }
        i = i + 1
    }
    locals
}
func mir_expr_type_name(expr value) string {
    switch value {
        expr.int(_) : return "int"
        expr.string(_) : return "string"
        expr.bool(_) : return "bool"
        expr.call(call_value) : {
            switch call_value.callee.unwrap() {
                expr.name(name_value) : {
                    if name_value.name == "box" || name_value.name == "box_new" {
                        return "box[unknown]"
                    }
                }
                _ : { }
            }
            if call_value.inferred_type.is_some() { return call_value.inferred_type.unwrap() }
        }
        _ : { }
    }
    "unknown"
}
func mir_expr_events(expr value, mir_local_slot[] locals, bool consume) string[] {
    events := string[]()
    switch value {
        expr.name(name_expr) : {
            local_id := mir_find_local(locals, name_expr.name)
            if local_id >= 0 {
                if consume && !locals[local_id].copyable {
                    events = append(events, "move:" + name_expr.name)
                } else {
                    events = append(events, "read:" + name_expr.name)
                }
            } else {
                events = append(events, "read:" + name_expr.name)
            }
        }
        expr.borrow(borrow_expr) : {
            target_events := mir_expr_events(borrow_expr.target.unwrap(), locals, false)
            events = mir_extend_events(events, target_events)
            target_name := mir_place_name(borrow_expr.target.unwrap())
            if target_name != "" {
                if borrow_expr.mutable { events = append(events, "mutable:" + target_name) }
                else { events = append(events, "shared:" + target_name) }
            }
        }
        expr.binary(binary_expr) : {
            events = mir_extend_events(events, mir_expr_events(binary_expr.left.unwrap(), locals, false))
            events = mir_extend_events(events, mir_expr_events(binary_expr.right.unwrap(), locals, false))
        }
        expr.call(call_expr) : {
            events = mir_extend_events(events, mir_expr_events(call_expr.callee.unwrap(), locals, false))
            i := 0
            for i < len(call_expr.args) {
                events = mir_extend_events(events, mir_expr_events(call_expr.args[i], locals, true))
                i = i + 1
            }
        }
        expr.member(member_expr) : {
            events = mir_extend_events(events, mir_expr_events(member_expr.target.unwrap(), locals, consume))
        }
        expr.index(index_expr) : {
            events = mir_extend_events(events, mir_expr_events(index_expr.target.unwrap(), locals, false))
            events = mir_extend_events(events, mir_expr_events(index_expr.index.unwrap(), locals, false))
        }
        expr.block(block_expr) : {
            i := 0
            for i < len(block_expr.statements) {
                events = mir_extend_events(events, mir_stmt_events(block_expr.statements[i], locals))
                i = i + 1
            }
            if block_expr.final_expr.is_some() { events = mir_extend_events(events, mir_expr_events(block_expr.final_expr.unwrap(), locals, consume)) }
        }
        _ : { }
    }
    events
}
func mir_place_name(expr value) string {
    mir_place_key(mir_place_from_expr(value))
}
func mir_append_ownership_semantics_from_stmt(mir_statement[] statements, stmt value) () {
    switch value {
        stmt.let(let_stmt) : {
            mir_append_ownership_semantics_from_expr(statements, let_stmt.value, let_stmt.name)
        }
        stmt.assign(assign_stmt) : {
            mir_append_ownership_semantics_from_expr(statements, assign_stmt.value, assign_stmt.name)
        }
        stmt.expr(expr_stmt) : {
            mir_append_ownership_semantics_from_expr(statements, expr_stmt.expr, "")
        }
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() {
                mir_append_ownership_semantics_from_expr(statements, return_stmt.value.unwrap(), "")
            }
        }
        stmt.defer(defer_stmt) : {
            mir_append_ownership_semantics_from_expr(statements, defer_stmt.expr, "")
        }
        stmt.sroutine(sroutine_stmt) : {
            mir_append_ownership_semantics_from_expr(statements, sroutine_stmt.expr, "")
        }
        _ : { }
    }
}
func mir_append_ownership_semantics_from_expr(mir_statement[] statements, expr value, string result_name) () {
    switch value {
        expr.borrow(borrow_expr) : {
            target := borrow_expr.target.unwrap()
            place := mir_place_from_expr(target)
            if result_name != "" && place.root != "" {
                statements.push(mir_statement::borrow(mir_borrow_stmt {
                    ref_name: result_name, place place, mutable borrow_expr.mutable,
                }))
            }
            mir_append_ownership_semantics_from_expr(statements, target, "")
        }
        expr.name(name_expr) : {
            if result_name != "" {
                statements.push(mir_statement::ref_assign(mir_ref_assign_stmt {
                    target_ref: result_name, source_ref name_expr.name,
                }))
            } else {
                statements.push(mir_statement::ref_use(mir_ref_use_stmt {
                    ref_name: name_expr.name,
                }))
            }
        }
        expr.binary(binary_expr) : {
            mir_append_ownership_semantics_from_expr(statements, binary_expr.left.unwrap(), "")
            mir_append_ownership_semantics_from_expr(statements, binary_expr.right.unwrap(), "")
        }
        expr.call(call_expr) : {
            mir_append_ownership_semantics_from_expr(statements, call_expr.callee.unwrap(), "")
            i := 0
            for i < len(call_expr.args) {
                mir_append_ownership_semantics_from_expr(statements, call_expr.args[i], "")
                i = i + 1
            }
        }
        expr.member(member_expr) : {
            mir_append_ownership_semantics_from_expr(statements, member_expr.target.unwrap(), result_name)
        }
        expr.index(index_expr) : {
            mir_append_ownership_semantics_from_expr(statements, index_expr.target.unwrap(), result_name)
            mir_append_ownership_semantics_from_expr(statements, index_expr.index.unwrap(), "")
        }
        expr.block(block_expr) : {
            i := 0
            for i < len(block_expr.statements) {
                mir_append_ownership_semantics_from_stmt(statements, block_expr.statements[i])
                i = i + 1
            }
            if block_expr.final_expr.is_some() {
                mir_append_ownership_semantics_from_expr(statements, block_expr.final_expr.unwrap(), result_name)
            }
        }
        _ : { }
    }
}
func mir_stmt_events(stmt value, mir_local_slot[] locals) string[] {
    events := string[]()
    switch value {
        stmt.let(let_stmt) : {
            events = mir_extend_events(events, mir_expr_events(let_stmt.value, locals, true))
        }
        stmt.assign(assign_stmt) : {
            events = mir_extend_events(events, mir_expr_events(assign_stmt.value, locals, true))
            events = append(events, "write:" + assign_stmt.name)
        }
        stmt.increment(increment_stmt) : {
            events = append(events, "read:" + increment_stmt.name)
            events = append(events, "write:" + increment_stmt.name)
        }
        stmt.expr(expr_stmt) : {
            events = mir_extend_events(events, mir_expr_events(expr_stmt.expr, locals, false))
        }
        stmt.return(return_stmt) : {
            if return_stmt.value.is_some() { events = mir_extend_events(events, mir_expr_events(return_stmt.value.unwrap(), locals, true)) }
        }
        stmt.defer(defer_stmt) : { events = mir_extend_events(events, mir_expr_events(defer_stmt.expr, locals, true)) }
        stmt.sroutine(sroutine_stmt) : { events = mir_extend_events(events, mir_expr_events(sroutine_stmt.expr, locals, true)) }
        _ : { }
    }
    events
}
func dump_graph(mir_graph graph) string {
    out := "mir " + graph.function_name
        + " blocks=" + std.prelude.to_string(len(graph.blocks))
        + " entry=" + std.prelude.to_string(graph.entry)
        + " exit=" + std.prelude.to_string(graph.exit)
    i := 0
    for i < len(graph.blocks) {
        block := graph.blocks[i]
        out = out + " | bb" + std.prelude.to_string(block.id)
            + "(" + block.label + ")"
            + " stmts=" + std.prelude.to_string(len(block.statements))
            + " term=" + block.terminator.kind
        i = i + 1
    }
    out
}
func block_count(mir_graph graph) int {
    len(graph.blocks)
}
func lower_function(function_decl function) string {
    graph := lower_function_graph(function)
    return analyze_borrow_function(function.sig.name, string[](), dump_graph(graph))
}
func lower_block(block_expr block) string {
    text := "block"
    index := 0
    for index < len(block.statements) {
        stmt_text := join_text(s.dump_stmt(block.statements[index], indent(1)), " | ")
        text = text + " | " + indent(1) + stmt_text
        index = index + 1
    }
    if block.final_expr.is_some() {
        tail := block.final_expr.unwrap()
        return text + " | " + indent(1) + "yield " + s.dump_expr(tail)
    } else {
        return text + " | " + indent(1) + "yield unit"
    }
}
func trace_branch(string condition_text, string then_text, string else_text) string {
    if else_text == "" {
        return "branch " + condition_text + " | " + indent(1) + "then " + then_text + " | " + indent(1) + "else <missing>"
    }
    return "branch " + condition_text + " | " + indent(1) + "then " + then_text + " | " + indent(1) + "else " + else_text
}
func trace_loop(string loop_kind, string condition_text, string body_text) string {
    return loop_kind + " " + condition_text + " | " + indent(1) + "body " + body_text
}
func trace_switch(string subject_text, string arms_text) string {
    if arms_text == "" {
        return "switch " + subject_text
    }
    return "switch " + subject_text + " | " + arms_text
}
func indent(int depth) string {
    out := ""
    i := 0
    for i < depth {
        out = out + "  "
        i = i + 1
    }
    return out
}
func join_text(string[] values, string sep) string {
    out := ""
    i := 0
    for i < len(values) {
        if i > 0 {
            out = out + sep
        }
        out = out + values[i]
        i = i + 1
    }
    return out
