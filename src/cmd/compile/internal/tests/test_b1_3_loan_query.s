package compile.internal.tests

import (
    "compile.internal.mir"
    "s"
    "std.prelude"
)

// B1.3: Loan→Place Query Test (Shadow Analysis Entry Point)
// Tests mir_loan_borrowed_place() with two different nested borrows
// Verifies:
//   1. Query returns correct place for valid loan_id
//   2. Query fails safely for out-of-bounds loan_id
//   3. Different loans return different places
//   4. Loan identity invariant: loan_count == len(loan_borrowed_places)

func test_b1_3_loan_borrowed_place_query() bool {
    // [1] Construct two different nested places
    // L0: owner.left.value
    place_l0 := mir_place_from_fields("owner", string[]{"left", "value"})
    
    // L1: other.right
    place_l1 := mir_place_from_fields("other", string[]{"right"})

    // [2] Create MIR with two borrow statements
    // Block: B0
    //   stmt 0: borrow L0 (r0 := &owner.left.value)
    //   stmt 1: borrow L1 (r1 := &other.right)
    borrow_stmt_l0 := mir_borrow_stmt{
        ref_name: "r0",
        place: place_l0,
        mutable: false,
    }

    borrow_stmt_l1 := mir_borrow_stmt{
        ref_name: "r1",
        place: place_l1,
        mutable: false,
    }

    block := mir_block{
        id: 0,
        label: "entry",
        statements: mir_statement[]{
            mir_statement::borrow(borrow_stmt_l0),
            mir_statement::borrow(borrow_stmt_l1),
        },
        terminator: mir_terminator_plain(),
    }

    graph := mir_graph{
        blocks: mir_block[]{block},
        entry_block_id: 0,
    }

    // [3] Extract facts
    point_map := mir.build_mir_point_map(graph)
    facts := mir.build_ownership_facts_from_mir(graph, point_map)

    // [4] Verify loan_count
    if facts.input.loan_count != 2 {
        s.println("FAIL: Expected 2 loans, got " + std.prelude.to_string(facts.input.loan_count))
        return false
    }

    // [5] INVARIANT: loan_count == len(loan_borrowed_places)
    if len(facts.loan_borrowed_places) != facts.input.loan_count {
        s.println("FAIL: Loan identity invariant violated")
        s.println("  loan_count: " + std.prelude.to_string(facts.input.loan_count))
        s.println("  loan_borrowed_places length: " + std.prelude.to_string(len(facts.loan_borrowed_places)))
        return false
    }

    // [6] Query L0: should succeed and return owner.left.value
    place_query_l0, ok_l0 := mir.mir_loan_borrowed_place(&facts, 0)
    if !ok_l0 {
        s.println("FAIL: Query L0 returned ok=false")
        return false
    }

    if !mir.mir_place_equal(place_query_l0, place_l0) {
        s.println("FAIL: Query L0 place mismatch")
        s.println("  Expected root: " + place_l0.root)
        s.println("  Actual root: " + place_query_l0.root)
        return false
    }

    // [7] Query L1: should succeed and return other.right
    place_query_l1, ok_l1 := mir.mir_loan_borrowed_place(&facts, 1)
    if !ok_l1 {
        s.println("FAIL: Query L1 returned ok=false")
        return false
    }

    if !mir.mir_place_equal(place_query_l1, place_l1) {
        s.println("FAIL: Query L1 place mismatch")
        s.println("  Expected root: " + place_l1.root)
        s.println("  Actual root: " + place_query_l1.root)
        return false
    }

    // [8] Query should return DIFFERENT places for L0 vs L1
    if mir.mir_place_equal(place_query_l0, place_query_l1) {
        s.println("FAIL: L0 and L1 should return different places")
        return false
    }

    // [9] Out-of-bounds queries should fail safely
    _, ok_invalid := mir.mir_loan_borrowed_place(&facts, -1)
    if ok_invalid {
        s.println("FAIL: Query with loan_id=-1 should fail")
        return false
    }

    _, ok_overflow := mir.mir_loan_borrowed_place(&facts, 2)
    if ok_overflow {
        s.println("FAIL: Query with loan_id=2 should fail (loan_count=2)")
        return false
    }

    _, ok_overflow_large := mir.mir_loan_borrowed_place(&facts, 100)
    if ok_overflow_large {
        s.println("FAIL: Query with loan_id=100 should fail")
        return false
    }

    // [10] Nil facts pointer should fail safely
    _, ok_nil := mir.mir_loan_borrowed_place(nil, 0)
    if ok_nil {
        s.println("FAIL: Query with nil facts should fail")
        return false
    }

    s.println("PASS: B1.3 loan borrowed place query test succeeded")
    return true
}

// Helper: test that legacy string paths are preserved (backward compat)
func test_b1_3_legacy_string_compatibility() bool {
    place := mir_place_from_fields("var", string[]{"field", "subfield"})

    borrow_stmt := mir_borrow_stmt{
        ref_name: "r0",
        place: place,
        mutable: true,
    }

    block := mir_block{
        id: 0,
        label: "entry",
        statements: mir_statement[]{
            mir_statement::borrow(borrow_stmt),
        },
        terminator: mir_terminator_plain(),
    }

    graph := mir_graph{
        blocks: mir_block[]{block},
        entry_block_id: 0,
    }

    point_map := mir.build_mir_point_map(graph)
    facts := mir.build_ownership_facts_from_mir(graph, point_map)

    // Verify legacy loan_places still exists
    if len(facts.loan_places) != 1 {
        s.println("FAIL: Legacy loan_places not preserved")
        return false
    }

    // Verify canonical loan_borrowed_places also exists
    if len(facts.loan_borrowed_places) != 1 {
        s.println("FAIL: Canonical loan_borrowed_places missing")
        return false
    }

    // Verify query works
    queried_place, ok := mir.mir_loan_borrowed_place(&facts, 0)
    if !ok || !mir.mir_place_equal(queried_place, place) {
        s.println("FAIL: Query result invalid")
        return false
    }

    s.println("PASS: B1.3 legacy string compatibility test succeeded")
    return true
}

// mir_terminator_plain: helper
func mir_terminator_plain() mir_terminator {
    mir_terminator::return(mir_return_stmt{})
}

// B1.3 Runner
func run_b1_3_tests() int {
    tests_passed := 0
    tests_total := 2

    if test_b1_3_loan_borrowed_place_query() {
        tests_passed = tests_passed + 1
    }

    if test_b1_3_legacy_string_compatibility() {
        tests_passed = tests_passed + 1
    }

    s.println("")
    s.println("B1.3 Tests: " + std.prelude.to_string(tests_passed) + "/" + std.prelude.to_string(tests_total) + " passed")

    if tests_passed == tests_total { 0 } else { 1 }
}
