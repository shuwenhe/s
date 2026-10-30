package compile.internal
func main() int {
    declaration := function_ssa_function { symbol: "lib.read", parameter_types: string[]{"string"}, result_types: string[]{"string"}, blocks: function_ssa_block[](), entry_block: -1, exit_block: -1 }
    if verify_ssa_function(declaration) != "" { return 1 }
    if !ssa_function_external(declaration) { return 2 }
    declaration.result_types = string[]{""}
    if verify_ssa_function(declaration) == "" { return 3 }
    declaration.result_types = string[]{"&int"}
    if verify_ssa_function(declaration) == "" { return 4 }
    declaration.result_types = string[]{"string"}
    declaration.parameter_types = string[]{""}
    if verify_ssa_function(declaration) == "" { return 5 }
    declaration.parameter_types = string[]{"string"}
    declaration.exit_block = 0
    if verify_ssa_function(declaration) == "" { return 6 }
    declaration.exit_block = -1
    declaration.blocks.push(function_ssa_block { id: 0, label: "entry", values: function_ssa_value[](), predecessors: int[](), successors: int[](), terminator: "unreachable", terminator_values: int[]() })
    if verify_ssa_function(declaration) == "" { return 7 }
    declaration.blocks = function_ssa_block[]()
    declaration.entry_block = 0
    declaration.exit_block = 0
    if verify_ssa_function(declaration) == "" { return 8 }
    return 0
}
