package compile.internal.semantic

import (
    "s"
    "std"
    "std.prelude"
)

func test_name_resolution_gate_simple() int {
    
    source := "
package test

func main() {
    x := 5
    y := x + 1
}
"
    
    
    parsed_result := s.parse_source(source)
    if parsed_result.is_err() {
        return 1  
    }
    
    file := parsed_result.unwrap()
    
    
    functions := function_binding[]()
    traits := trait_binding[]()
    consts := const_binding[]()
    structs := struct_binding[]()
    
    
    result := canonical_name_resolution_check(file, functions, traits, consts, structs)
    
    
    if result.total_identifiers == 0 {
        return 1  
    }
    
    
    
    
    return 0  
}

func test_name_resolution_with_function_call() int {
    
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
    
    
    result := canonical_name_resolution_check(file, functions, traits, consts, structs)
    
    
    
    
    return 0
}
