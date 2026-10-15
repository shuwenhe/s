package compile.internal.ssa

struct ssa_value {
    int id
    string op
    int[] operands
    int block_id
    string type_name
}

struct ssa_block {
    int id
    string label
    ssa_value[] values
    int[] predecessors
    int[] successors
    string terminator
    int[] terminator_values
}

struct ssa_function {
    string symbol
    string[] parameter_types
    string[] result_types
    ssa_block[] blocks
    int entry_block
    int exit_block
}

struct ssa_call {
    string caller
    string callee
    int block_id
    int value_id
}

struct ssa_program {
    string package_name
    string entry_symbol
    ssa_function[] functions
    ssa_call[] calls
}

func ssa_function_index(ssa_function[] functions, string symbol) int {
    i := 0
    for i < len(functions) {
        if functions[i].symbol == symbol { return i }
        i = i + 1
    }
    return -1
}

func ssa_block_index(ssa_block[] blocks, int id) int {
    i := 0
    for i < len(blocks) {
        if blocks[i].id == id { return i }
        i = i + 1
    }
    return -1
}

func ssa_value_exists(ssa_block[] blocks, int id) bool {
    b := 0
    for b < len(blocks) {
        v := 0
        for v < len(blocks[b].values) {
            if blocks[b].values[v].id == id { return true }
            v = v + 1
        }
        b = b + 1
    }
    return false
}

func verify_ssa_function(ssa_function f) string {
    if f.symbol == "" { return "empty function symbol" }
    if len(f.blocks) == 0 { return "function has no blocks: " + f.symbol }
    if ssa_block_index(f.blocks, f.entry_block) < 0 { return "missing entry block: " + f.symbol }
    if f.exit_block >= 0 && ssa_block_index(f.blocks, f.exit_block) < 0 { return "missing exit block: " + f.symbol }
    b := 0
    for b < len(f.blocks) {
        block := f.blocks[b]
        if block.id < 0 || block.label == "" { return "invalid block: " + f.symbol }
        if ssa_block_index(f.blocks, block.id) != b { return "duplicate block: " + f.symbol }
        p := 0
        for p < len(block.predecessors) {
            if ssa_block_index(f.blocks, block.predecessors[p]) < 0 { return "unknown predecessor: " + f.symbol }
            p = p + 1
        }
        s := 0
        for s < len(block.successors) {
            if ssa_block_index(f.blocks, block.successors[s]) < 0 { return "unknown successor: " + f.symbol }
            s = s + 1
        }
        v := 0
        for v < len(block.values) {
            value := block.values[v]
            if value.id < 0 || value.op == "" || value.type_name == "" { return "invalid value: " + f.symbol }
            other := 0
            for other < len(f.blocks) {
                ov := 0
                for ov < len(f.blocks[other].values) {
                    if other != b && f.blocks[other].values[ov].id == value.id { return "duplicate value: " + f.symbol }
                    ov = ov + 1
                }
                other = other + 1
            }
            a := 0
            for a < len(value.operands) {
                if !ssa_value_exists(f.blocks, value.operands[a]) { return "unknown operand: " + f.symbol }
                a = a + 1
            }
            v = v + 1
        }
        b = b + 1
    }
    return ""
}

func verify_ssa_program(ssa_program program) string {
    if program.package_name == "" || program.entry_symbol == "" { return "invalid program identity" }
    if ssa_function_index(program.functions, program.entry_symbol) < 0 { return "missing entry function" }
    i := 0
    for i < len(program.functions) {
        if ssa_function_index(program.functions, program.functions[i].symbol) != i { return "duplicate function" }
        error := verify_ssa_function(program.functions[i])
        if error != "" { return error }
        i = i + 1
    }
    i = 0
    for i < len(program.calls) {
        call := program.calls[i]
        caller := ssa_function_index(program.functions, call.caller)
        callee := ssa_function_index(program.functions, call.callee)
        if caller < 0 || callee < 0 { return "unknown call edge" }
        if ssa_block_index(program.functions[caller].blocks, call.block_id) < 0 { return "unknown call block" }
        i = i + 1
    }
    return ""
}
