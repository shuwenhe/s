package compile.internal

import (
    "compile.internal.semantic"
    "compile.internal.syntax"
    "s"
    "std.fs"
    "std.result"
)

func run_stage5_gate_on_file(string filepath) compile.internal.semantic.name_resolution_gate_result {
    
    read_result := std.fs.read_to_string(filepath)
    if read_result.is_err() {
        return compile.internal.semantic.name_resolution_gate_result {
            total_identifiers: 0,
            resolved_exact: 0,
            resolved_ambiguous: 0,
            unresolved: 0,
            qualified_with_multiple_matches: 0,
            details: compile.internal.semantic.identifier_resolution[](),
            gate_pass: 0,
        }
    }
    source := read_result.unwrap()
    
    
    file, parse_error := compile.internal.syntax.parse_source(source)
    if parse_error.message != "" {
        return compile.internal.semantic.name_resolution_gate_result {
            total_identifiers: 0, resolved_exact: 0, resolved_ambiguous: 0,
            unresolved: 0, qualified_with_multiple_matches: 0,
            details: compile.internal.semantic.identifier_resolution[](), gate_pass: 0,
        }
    }

    functions := compile.internal.semantic.collect_functions(file)
    traits := compile.internal.semantic.collect_traits(file)
    consts := compile.internal.semantic.collect_consts(file, functions, traits, source, compile.internal.semantic.semantic_error[]())
    structs := compile.internal.semantic.collect_structs(file)
    
    
    return compile.internal.semantic.name_resolution_gate_result {
        total_identifiers: 0,
        resolved_exact: 0,
        resolved_ambiguous: 0,
        unresolved: 0,
        qualified_with_multiple_matches: 0,
        details: compile.internal.semantic.identifier_resolution[](),
        gate_pass: 0,
    }
}

func test_gate_on_main() int {
    result := run_stage5_gate_on_file("src/cmd/compile/main.s")
    
    
    if result.total_identifiers == 0 {
        return 1  
    }
    
    if result.gate_pass == 0 {
        
        if result.unresolved > 0 {
            return 1  
        }
    }
    
    return 0  
}
