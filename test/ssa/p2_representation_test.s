package compile.internal.ssa

func empty_values() function_ssa_value[] { return function_ssa_value[]() }
func empty_blocks() function_ssa_block[] { return function_ssa_block[]() }
func empty_functions() function_ssa_function[] { return function_ssa_function[]() }
func empty_calls() function_ssa_call[] { return function_ssa_call[]() }

func main() int {
    values := empty_values()
    values.push(function_ssa_value { id: 0, op: "const_int", operands: int[](), block_id: 0, type_name: "int" })
    block := function_ssa_block {
        id: 0, label: "entry", values: values,
        predecessors: int[](), successors: int[](), terminator: "return", terminator_values: int[]{0},
    }
    blocks := empty_blocks()
    blocks.push(block)
    functions := empty_functions()
    functions.push(function_ssa_function {
        symbol: "sample.main", parameter_types: string[](), result_types: string[]{"int"},
        blocks: blocks, entry_block: 0, exit_block: 0,
    })
    program := function_ssa_program {
        package_name: "sample", entry_symbol: "sample.main", functions: functions, calls: empty_calls(),
    }
    if verify_ssa_program(program) != "" { return 1 }

    bad := function_ssa_value { id: 2, op: "add", operands: int[]{99}, block_id: 0, type_name: "int" }
    values.push(bad)
    blocks[0] = function_ssa_block {
        id: 0, label: "entry", values: values,
        predecessors: int[](), successors: int[](), terminator: "return", terminator_values: int[]{0},
    }
    functions[0] = function_ssa_function {
        symbol: "sample.main", parameter_types: string[](), result_types: string[]{"int"},
        blocks: blocks, entry_block: 0, exit_block: 0,
    }
    bad_program := function_ssa_program {
        package_name: "sample", entry_symbol: "sample.main", functions: functions, calls: empty_calls(),
    }
    if verify_ssa_program(bad_program) != "unknown operand: sample.main" { return 2 }
    eprintln("P2.1 SSA representation and verifier PASS")
    return 0
}
