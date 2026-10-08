package compile.internal.tests

import (
    "compile.internal.mir"
    "s"
    "std.prelude"
)

func test_b1_2_borrow_place_preservation() bool {
    
    
    
    
    nested_place := mir_place {
        root: "owner",
        projections: mir_place_projection[]{
            mir_place_projection {
                kind: mir_projection_kind::field,
                value: "inner",
            },
            mir_place_projection {
                kind: mir_projection_kind::field,
                value: "value",
            },
        },
    }

    
    borrow_stmt := mir_borrow_stmt {
        ref_name: "r0",
        place: nested_place,
        mutable: false,
    }

    block := mir_block {
        id: 0,
        label: "entry",
        statements: mir_statement[]{
            mir_statement::mir_borrow(borrow_stmt),
        },
        terminator: mir_terminator_plain(),
    }

    graph := mir_graph {
        blocks: mir_block[]{block},
        entry_block_id: 0,
    }

    
    point_map := mir.build_mir_point_map(graph)
    facts := mir.build_ownership_facts_from_mir(graph, point_map)

    
    if facts.input.loan_count != 1 {
        s.println("FAIL: Expected 1 loan, got " + std.prelude.to_string(facts.input.loan_count))
        return false
    }

    
    if len(facts.loan_borrowed_places) != 1 {
        s.println("FAIL: Expected 1 loan_borrowed_place, got " + std.prelude.to_string(len(facts.loan_borrowed_places)))
        return false
    }

    actual_place := facts.loan_borrowed_places[0]

    
    
    if !mir.mir_place_equal(nested_place, actual_place) {
        s.println("FAIL: Nested place not structurally equal")
        s.println("  Expected root: " + nested_place.root)
        s.println("  Actual root: " + actual_place.root)
        s.println("  Expected projections: " + std.prelude.to_string(len(nested_place.projections)))
        s.println("  Actual projections: " + std.prelude.to_string(len(actual_place.projections)))
        return false
    }

    
    if len(actual_place.projections) != 2 {
        s.println("FAIL: Expected 2 projections, got " + std.prelude.to_string(len(actual_place.projections)))
        return false
    }

    
    if actual_place.projections[0].kind != mir_projection_kind::field {
        s.println("FAIL: Projection 0 kind is not field")
        return false
    }
    if actual_place.projections[0].value != "inner" {
        s.println("FAIL: Projection 0 value is not 'inner', got: " + actual_place.projections[0].value)
        return false
    }

    
    if actual_place.projections[1].kind != mir_projection_kind::field {
        s.println("FAIL: Projection 1 kind is not field")
        return false
    }
    if actual_place.projections[1].value != "value" {
        s.println("FAIL: Projection 1 value is not 'value', got: " + actual_place.projections[1].value)
        return false
    }

    
    if len(facts.loan_places) != 1 {
        s.println("FAIL: Expected 1 legacy loan_place string, got " + std.prelude.to_string(len(facts.loan_places)))
        return false
    }

    
    expected_key := mir.mir_place_key(nested_place)
    if facts.loan_places[0] != expected_key {
        s.println("FAIL: Legacy loan_place string mismatch")
        s.println("  Expected: " + expected_key)
        s.println("  Actual: " + facts.loan_places[0])
        return false
    }

    
    if facts.input.point_count != len(point_map.points) {
        s.println("FAIL: Point count mismatch in input")
        return false
    }

    if facts.input.loan_count != 1 {
        s.println("FAIL: Loan count in input is wrong")
        return false
    }

    
    if len(facts.input.loan_points) != 1 {
        s.println("FAIL: LoanLivePoints not recorded")
        return false
    }

    s.println("PASS: B1.2 nested place preservation test succeeded")
    return true
}

func mir_terminator_plain() mir_terminator {
    mir_terminator::return(mir_return_stmt{})
}

func run_b1_2_tests() int {
    tests_passed := 0
    tests_total := 1

    if test_b1_2_borrow_place_preservation() {
        tests_passed = tests_passed + 1
    }

    s.println("")
    s.println("B1.2 Tests: " + std.prelude.to_string(tests_passed) + "/" + std.prelude.to_string(tests_total) + " passed")

    if tests_passed == tests_total { 0 } else { 1 }
}
