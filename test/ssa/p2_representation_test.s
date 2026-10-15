package compile.internal.ssa

func empty_values() ssa_value[] { return ssa_value[]() }
func empty_blocks() ssa_block[] { return ssa_block[]() }
func empty_functions() ssa_function[] { return ssa_function[]() }
func empty_calls() ssa_call[] { return ssa_call[]() }

func main() int {
    values := empty_values()
    values.push(ssa_value { id: 0, op: "const_int", operands: int[](), block_id: 0, type_name: "int" })
    block := ssa_block {
        id: 0, label: "entry", values: values,
        predecessors: int[](), successors: int[](), terminator: "return", terminator_values: int[]{0},
    }
    blocks := empty_blocks()
    blocks.push(block)
    functions := empty_functions()
    functions.push(ssa_function {
        symbol: "sample.main", parameter_types: string[](), result_types: string[]{"int"},
        blocks: blocks, entry_block: 0, exit_block: 0,
    })
    program := ssa_program {
        package_name: "sample", entry_symbol: "sample.main", functions: functions, calls: empty_calls(),
    }
    if verify_ssa_program(program) != "" { return 1 }

    bad := ssa_value { id: 2, op: "add", operands: int[]{99}, block_id: 0, type_name: "int" }
    values.push(bad)
    blocks[0] = ssa_block {
        id: 0, label: "entry", values: values,
        predecessors: int[](), successors: int[](), terminator: "return", terminator_values: int[]{0},
    }
    functions[0] = ssa_function {
        symbol: "sample.main", parameter_types: string[](), result_types: string[]{"int"},
        blocks: blocks, entry_block: 0, exit_block: 0,
    }
    bad_program := ssa_program {
        package_name: "sample", entry_symbol: "sample.main", functions: functions, calls: empty_calls(),
    }
    if verify_ssa_program(bad_program) != "unknown operand: sample.main" { return 2 }
    eprintln("P2.1 SSA representation and verifier PASS")
    return 0
}
