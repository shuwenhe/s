package compile.internal.ssa

struct function_ssa_value {
    int id
    string op
    // Phi operands correspond to the owning block's predecessor order.
    int[] operands
    int block_id
    string type_name
    int integer_value
    int parameter_index
}

struct function_ssa_block {
    int id
    string label
    function_ssa_value[] values
    int[] predecessors
    int[] successors
    string terminator
    int[] terminator_values
}

struct function_ssa_function {
    string symbol
    string[] parameter_types
    string[] result_types
    function_ssa_block[] blocks
    int entry_block
    int exit_block
}

struct function_ssa_call {
    string caller
    // The edge records the direct target of its caller's call value.
    string callee
    int block_id
    int value_id
}

struct function_ssa_program {
    string package_name
    string entry_symbol
    function_ssa_function[] functions
    function_ssa_call[] calls
}

func ssa_function_index(function_ssa_function[] functions, string symbol) int {
    i := 0
    for i < len(functions) {
        if functions[i].symbol == symbol { return i }
        i = i + 1
    }
    return -1
}

func ssa_block_index(function_ssa_block[] blocks, int id) int {
    i := 0
    for i < len(blocks) {
        if blocks[i].id == id { return i }
        i = i + 1
    }
    return -1
}

func ssa_value_exists(function_ssa_block[] blocks, int id) bool {
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

func ssa_value_index(function_ssa_value[] values, int id) int {
    i := 0
    for i < len(values) {
        if values[i].id == id { return i }
        i = i + 1
    }
    return -1
}

func ssa_value_block_index(function_ssa_block[] blocks, int id) int {
    b := 0
    for b < len(blocks) {
        if ssa_value_index(blocks[b].values, id) >= 0 { return b }
        b = b + 1
    }
    return -1
}

func ssa_value_type(function_ssa_block[] blocks, int id) string {
    b := ssa_value_block_index(blocks, id)
    if b < 0 { return "" }
    return blocks[b].values[ssa_value_index(blocks[b].values, id)].type_name
}

func ssa_edge_count(int[] edges, int id) int {
    count := 0
    i := 0
    for i < len(edges) {
        if edges[i] == id { count = count + 1 }
        i = i + 1
    }
    return count
}

// Indices in these work arrays refer to f.blocks, not to possibly sparse IDs.
// Excluding a block lets the verifier test dominance without assuming that
// blocks are stored in traversal order or that the graph has no backedges.
func ssa_reachable_blocks(function_ssa_function f, int excluded) int[] {
    reachable := int[]()
    b := 0
    for b < len(f.blocks) {
        reachable.push(0)
        b = b + 1
    }
    entry := ssa_block_index(f.blocks, f.entry_block)
    if entry == excluded { return reachable }
    pending := int[]()
    pending.push(entry)
    reachable[entry] = 1
    i := 0
    for i < len(pending) {
        block := f.blocks[pending[i]]
        s := 0
        for s < len(block.successors) {
            next := ssa_block_index(f.blocks, block.successors[s])
            if next != excluded && reachable[next] == 0 {
                reachable[next] = 1
                pending.push(next)
            }
            s = s + 1
        }
        i = i + 1
    }
    return reachable
}

func ssa_dominance_matrix(function_ssa_function f) int[] {
    reachable := ssa_reachable_blocks(f, -1)
    dominance := int[]()
    defining := 0
    for defining < len(f.blocks) {
        without := ssa_reachable_blocks(f, defining)
        using := 0
        for using < len(f.blocks) {
            // Like Go's domCheck, unreachable uses do not constrain dominance.
            dominates := 0
            if reachable[using] == 0 || defining == using || without[using] == 0 { dominates = 1 }
            dominance.push(dominates)
            using = using + 1
        }
        defining = defining + 1
    }
    return dominance
}

func ssa_value_use_error(function_ssa_function f, int[] dominance, int id, int use_block, int use_position) string {
    defining := ssa_value_block_index(f.blocks, id)
    if defining < 0 { return "unknown operand: " + f.symbol }
    if defining == use_block && ssa_value_index(f.blocks[defining].values, id) >= use_position {
        return "forward operand: " + f.symbol
    }
    if dominance[defining * len(f.blocks) + use_block] == 0 { return "nondominating operand: " + f.symbol }
    return ""
}

func verify_ssa_function(function_ssa_function f) string {
    if f.symbol == "" { return "empty function symbol" }
    if len(f.blocks) == 0 { return "function has no blocks: " + f.symbol }
    if ssa_block_index(f.blocks, f.entry_block) < 0 { return "missing entry block: " + f.symbol }
    if f.exit_block >= 0 && ssa_block_index(f.blocks, f.exit_block) < 0 { return "missing exit block: " + f.symbol }
    if len(f.blocks[ssa_block_index(f.blocks, f.entry_block)].predecessors) != 0 { return "entry block has predecessors: " + f.symbol }
    t := 0
    for t < len(f.parameter_types) {
        if f.parameter_types[t] == "" { return "empty parameter type: " + f.symbol }
        t = t + 1
    }
    t = 0
    for t < len(f.result_types) {
        if f.result_types[t] == "" { return "empty result type: " + f.symbol }
        t = t + 1
    }
    b := 0
    for b < len(f.blocks) {
        block := f.blocks[b]
        if block.id < 0 || block.label == "" { return "invalid block: " + f.symbol }
        if ssa_block_index(f.blocks, block.id) != b { return "duplicate block: " + f.symbol }
        p := 0
        for p < len(block.predecessors) {
            predecessor := ssa_block_index(f.blocks, block.predecessors[p])
            if predecessor < 0 { return "unknown predecessor: " + f.symbol }
            if ssa_edge_count(block.predecessors, block.predecessors[p]) != ssa_edge_count(f.blocks[predecessor].successors, block.id) {
                return "inconsistent predecessor edge: " + f.symbol
            }
            p = p + 1
        }
        s := 0
        for s < len(block.successors) {
            successor := ssa_block_index(f.blocks, block.successors[s])
            if successor < 0 { return "unknown successor: " + f.symbol }
            if ssa_edge_count(block.successors, block.successors[s]) != ssa_edge_count(f.blocks[successor].predecessors, block.id) {
                return "inconsistent successor edge: " + f.symbol
            }
            s = s + 1
        }
        v := 0
        for v < len(block.values) {
            value := block.values[v]
            if value.id < 0 || value.op == "" || value.type_name == "" { return "invalid value: " + f.symbol }
            if value.block_id != block.id { return "value block mismatch: " + f.symbol }
            if ssa_value_block_index(f.blocks, value.id) != b || ssa_value_index(block.values, value.id) != v { return "duplicate value: " + f.symbol }
            if value.op == "phi" && len(value.operands) != len(block.predecessors) { return "phi operand count: " + f.symbol }
            a := 0
            for a < len(value.operands) {
                if !ssa_value_exists(f.blocks, value.operands[a]) { return "unknown operand: " + f.symbol }
                if value.op == "phi" && ssa_value_type(f.blocks, value.operands[a]) != value.type_name { return "phi operand type: " + f.symbol }
                a = a + 1
            }
            v = v + 1
        }
        if block.terminator == "return" {
            if len(block.successors) != 0 { return "return has successors: " + f.symbol }
            if len(block.terminator_values) != len(f.result_types) { return "return count: " + f.symbol }
        } else if block.terminator == "jump" {
            if len(block.successors) != 1 || len(block.terminator_values) != 0 { return "invalid jump: " + f.symbol }
        } else if block.terminator == "branch" {
            if len(block.successors) != 2 || len(block.terminator_values) != 1 { return "invalid branch: " + f.symbol }
        } else {
            return "unsupported terminator: " + f.symbol
        }
        a := 0
        for a < len(block.terminator_values) {
            actual := ssa_value_type(f.blocks, block.terminator_values[a])
            if actual == "" { return "unknown terminator value: " + f.symbol }
            if block.terminator == "branch" && actual != "bool" { return "branch condition type: " + f.symbol }
            if block.terminator == "return" && actual != f.result_types[a] { return "return type: " + f.symbol }
            a = a + 1
        }
        b = b + 1
    }
    dominance := ssa_dominance_matrix(f)
    b = 0
    for b < len(f.blocks) {
        block := f.blocks[b]
        v := 0
        for v < len(block.values) {
            value := block.values[v]
            a := 0
            for a < len(value.operands) {
                use_block := b
                use_position := v
                if value.op == "phi" {
                    // A phi's ith input is used on the ith incoming edge,
                    // after all values in that predecessor have been defined.
                    use_block = ssa_block_index(f.blocks, block.predecessors[a])
                    use_position = len(f.blocks[use_block].values)
                }
                error := ssa_value_use_error(f, dominance, value.operands[a], use_block, use_position)
                if error != "" { return error }
                a = a + 1
            }
            v = v + 1
        }
        a := 0
        for a < len(block.terminator_values) {
            error := ssa_value_use_error(f, dominance, block.terminator_values[a], b, len(block.values))
            if error != "" { return error }
            a = a + 1
        }
        b = b + 1
    }
    return ""
}

func verify_ssa_program(function_ssa_program program) string {
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
        block := ssa_block_index(program.functions[caller].blocks, call.block_id)
        if block < 0 { return "unknown call block" }
        value_index := ssa_value_index(program.functions[caller].blocks[block].values, call.value_id)
        if value_index < 0 { return "unknown call value" }
        value := program.functions[caller].blocks[block].values[value_index]
        if value.op != "call" { return "call edge references non-call value" }
        previous := 0
        for previous < i {
            edge := program.calls[previous]
            if edge.caller == call.caller && edge.block_id == call.block_id && edge.value_id == call.value_id { return "duplicate call edge" }
            previous = previous + 1
        }
        target := program.functions[callee]
        if len(value.operands) != len(target.parameter_types) { return "call argument count: " + call.callee }
        a := 0
        for a < len(value.operands) {
            if ssa_value_type(program.functions[caller].blocks, value.operands[a]) != target.parameter_types[a] { return "call argument type: " + call.callee }
            a = a + 1
        }
        // This representation has one type per call value, so a call can
        // produce one scalar or void. Multiple results need explicit values.
        if len(target.result_types) > 1 { return "unsupported multi-result call: " + call.callee }
        if len(target.result_types) == 0 {
            if value.type_name != "void" { return "call result type: " + call.callee }
        } else if value.type_name != target.result_types[0] {
            return "call result type: " + call.callee
        }
        i = i + 1
    }
    i = 0
    for i < len(program.functions) {
        f := program.functions[i]
        b := 0
        for b < len(f.blocks) {
            v := 0
            for v < len(f.blocks[b].values) {
                value := f.blocks[b].values[v]
                if value.op == "call" {
                    count := 0
                    c := 0
                    for c < len(program.calls) {
                        call := program.calls[c]
                        if call.caller == f.symbol && call.block_id == f.blocks[b].id && call.value_id == value.id { count = count + 1 }
                        c = c + 1
                    }
                    if count != 1 { return "missing call edge: " + f.symbol }
                }
                v = v + 1
            }
            b = b + 1
        }
        i = i + 1
    }
    return ""
}
