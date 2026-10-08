package compile.internal.tests

import (
    "compile.internal.mir"
    "s"
    "std.prelude"
)

func test_b1_3_loan_borrowed_place_query() bool {
    
    
    place_l0 := mir_place_from_fields("owner", string[]{"left", "value"})
    
    
    place_l1 := mir_place_from_fields("other", string[]{"right"})

    
    
    
    
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
            mir_statement::mir_borrow(borrow_stmt_l0),
            mir_statement::mir_borrow(borrow_stmt_l1),
        },
        terminator: mir_terminator_plain(),
    }

    graph := mir_graph{
        blocks: mir_block[]{block},
        entry_block_id: 0,
    }

    
    point_map := mir.build_mir_point_map(graph)
    facts := mir.build_ownership_facts_from_mir(graph, point_map)

    
    if facts.input.loan_count != 2 {
        s.println("FAIL: Expected 2 loans, got " + std.prelude.to_string(facts.input.loan_count))
        return false
    }

    
    if len(facts.loan_borrowed_places) != facts.input.loan_count {
        s.println("FAIL: Loan identity invariant violated")
        s.println("  loan_count: " + std.prelude.to_string(facts.input.loan_count))
        s.println("  loan_borrowed_places length: " + std.prelude.to_string(len(facts.loan_borrowed_places)))
        return false
    }

    
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

    
    if mir.mir_place_equal(place_query_l0, place_query_l1) {
        s.println("FAIL: L0 and L1 should return different places")
        return false
    }

    
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

    
    _, ok_nil := mir.mir_loan_borrowed_place(nil, 0)
    if ok_nil {
        s.println("FAIL: Query with nil facts should fail")
        return false
    }

    s.println("PASS: B1.3 loan borrowed place query test succeeded")
    return true
}

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
            mir_statement::mir_borrow(borrow_stmt),
        },
        terminator: mir_terminator_plain(),
    }

    graph := mir_graph{
        blocks: mir_block[]{block},
        entry_block_id: 0,
    }

    point_map := mir.build_mir_point_map(graph)
    facts := mir.build_ownership_facts_from_mir(graph, point_map)

    
    if len(facts.loan_places) != 1 {
        s.println("FAIL: Legacy loan_places not preserved")
        return false
    }

    
    if len(facts.loan_borrowed_places) != 1 {
        s.println("FAIL: Canonical loan_borrowed_places missing")
        return false
    }

    
    queried_place, ok := mir.mir_loan_borrowed_place(&facts, 0)
    if !ok || !mir.mir_place_equal(queried_place, place) {
        s.println("FAIL: Query result invalid")
        return false
    }

    s.println("PASS: B1.3 legacy string compatibility test succeeded")
    return true
}

func mir_terminator_plain() mir_terminator {
    mir_terminator::return(mir_return_stmt{})
}

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
