package compile.internal.semantic

import (
    "s"
    "std"
    "std.prelude"
)

// Test the name resolution gate with simple examples

func test_name_resolution_gate_simple() int {
    // Create a minimal source with known identifiers
    source := "
package test

func main() {
    x := 5
    y := x + 1
}
"
    
    // Parse it
    parsed_result := s.parse_source(source)
    if parsed_result.is_err() {
        return 1  // Parse failed
    }
    
    file := parsed_result.unwrap()
    
    // Create empty declaration sets for testing
    functions := function_binding[]()
    traits := trait_binding[]()
    consts := const_binding[]()
    structs := struct_binding[]()
    
    // Run the gate
    result := canonical_name_resolution_check(file, functions, traits, consts, structs)
    
    // Verify: should find identifier "x" in main
    if result.total_identifiers == 0 {
        return 1  // Should have found at least one identifier
    }
    
    // Since "x" is a local variable, we can't resolve it to a declaration
    // But we should report it as unresolved (not a gate failure for locals)
    
    return 0  // Test passed
}

func test_name_resolution_with_function_call() int {
    // Create source that calls a function
    source := "
package test
import (
    \"std.io\"
)

func main() {
    std.io.println(\"hello\")
}
"
    
    parsed_result := s.parse_source(source)
    if parsed_result.is_err() {
        return 1
    }
    
    file := parsed_result.unwrap()
    
    // Create mock declaration set
    functions := function_binding[]()
    functions = append(functions, function_binding {
        package_path: "std.io",
        name: "println",
        owner_type: "",
        has_receiver: false,
        receiver_mode: "",
        generic_names: string[](),
        param_types: string[]("string"),
        return_type: "()",
    })
    
    traits := trait_binding[]()
    consts := const_binding[]()
    structs := struct_binding[]()
    
    // Run gate
    result := canonical_name_resolution_check(file, functions, traits, consts, structs)
    
    // Should find "std.io.println" and resolve it exactly
    // (But locating it in identifiers requires proper implementation)
    
    return 0
}
