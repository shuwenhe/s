package compile.internal

import (
    "compile.internal.semantic"
    "compile.internal.syntax"
    "s"
    "std.fs"
    "std.result"
)

func run_stage5_gate_on_file(string filepath) semantic.name_resolution_gate_result {
    
    read_result := std.fs.read_to_string(filepath)
    source := switch read_result {
        source : source,
        err : {
            
            return semantic.name_resolution_gate_result {
                total_identifiers: 0,
                resolved_exact: 0,
                resolved_ambiguous: 0,
                unresolved: 0,
                qualified_with_multiple_matches: 0,
                details: semantic.identifier_resolution[](),
                gate_pass: 0,
            }
        },
    }
    
    
    parse_result := compile.internal.syntax.parse_source(source)
    file := switch parse_result {
        result.ok(parsed) : parsed,
        result.err(_) : {
            return semantic.name_resolution_gate_result {
                total_identifiers: 0,
                resolved_exact: 0,
                resolved_ambiguous: 0,
                unresolved: 0,
                qualified_with_multiple_matches: 0,
                details: semantic.identifier_resolution[](),
                gate_pass: 0,
            }
        },
    }
    
    
    functions := semantic.collect_functions(file)
    traits := semantic.collect_traits(file)
    consts := semantic.collect_consts(file, functions, traits, source, semantic.semantic_error[]())
    structs := semantic.collect_structs(file)
    
    
    semantic.canonical_name_resolution_check(file, functions, traits, consts, structs)
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
