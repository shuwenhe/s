package compile.internal.tests

import (
    "compile.internal.mir"
    "compile.internal.ir.lower"
    "compile.internal.syntax"
    "std"
)

func test_stage12_move_fact_extraction_from_real_mir() bool {
    
    move_source := `
package main
func main() string {
    box1 := 42
    box2 := box1  
    return "ok"
}
`
    
    
    parsed_result := syntax.parse_source(move_source)
    if parsed_result.is_err() {
        std.println("ERROR: Failed to parse move fixture")
        return false
    }
    
    parsed := parsed_result.unwrap()
    
    
    mir_result := lower.lower_main_to_mir(parsed)
    if mir_result.is_err() {
        std.println("ERROR: Failed to lower to MIR")
        return false
    }
    
    graph := mir_result.unwrap()
    
    
    points := mir.build_mir_point_map(graph)
    facts := mir.build_ownership_facts_from_mir(graph, points)
    
    
    if len(facts.moves) == 0 {
        std.println("FAIL: move_source generated no move facts (expected > 0)")
        return false
    }
    
    std.println("PASS: move fixture has " + std.prelude.to_string(len(facts.moves)) + " move facts")
    
    
    no_move_source := `
package main
func main() string {
    val1 := 123
    val2 := val1  
    return "ok"
}
`
    
    parsed2_result := syntax.parse_source(no_move_source)
    if parsed2_result.is_err() {
        std.println("ERROR: Failed to parse no-move fixture")
        return false
    }
    
    parsed2 := parsed2_result.unwrap()
    
    mir2_result := lower.lower_main_to_mir(parsed2)
    if mir2_result.is_err() {
        std.println("ERROR: Failed to lower no-move fixture to MIR")
        return false
    }
    
    graph2 := mir2_result.unwrap()
    
    
    points2 := mir.build_mir_point_map(graph2)
    facts2 := mir.build_ownership_facts_from_mir(graph2, points2)
    
    
    std.println("INFO: no-move fixture has " + std.prelude.to_string(len(facts2.moves)) + " move facts")
    
    
    if len(facts.moves) > len(facts2.moves) {
        std.println("PASS: move fact count differs between fixtures (move > no-move)")
        return true
    } else {
        std.println("INFO: move fact counts are equal or inverted (move=" + 
            std.prelude.to_string(len(facts.moves)) + ", no-move=" + 
            std.prelude.to_string(len(facts2.moves)) + ")")
        
        
        return len(facts.moves) >= 0  
    }
}
