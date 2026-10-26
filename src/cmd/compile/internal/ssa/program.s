package compile.internal

extern "intrinsic" func __host_slice(string text, int start, int end) string

struct function_ssa_record {
    string symbol
    string[] field_names
    string[] field_types
}

struct function_ssa_value {
    string symbol
    string[] field_names
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
    function_ssa_record[] records
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

// Indices: in these work arrays refer to f.blocks, not to possibly sparse IDs.
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
            // Like: Go's domCheck, unreachable uses do not constrain dominance.
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
            if ssa_is_scalar_operation(value.op) {
                scalar_error := ssa_scalar_value_error(f, value)
                if scalar_error != "" { return scalar_error }
            }
            if value.op == "const_unit" && (value.type_name != "()" || len(value.operands) != 0 || value.integer_value != 0) { return "invalid unit constant: " + f.symbol }
            if value.op == "const_int" && (value.type_name != "int" || len(value.operands) != 0) { return "invalid integer constant: " + f.symbol }
            if value.op == "copy" {
                if len(value.operands) != 1 { return "invalid copy: " + f.symbol }
                if ssa_value_type(f.blocks, value.operands[0]) != value.type_name { return "copy type: " + f.symbol }
            }
            if value.op == "param" {
                if block.id != f.entry_block { return "parameter outside entry block" }
                if value.parameter_index < 0 || value.parameter_index >= len(f.parameter_types) { return "parameter index: " + f.symbol }
                if value.type_name != f.parameter_types[value.parameter_index] || len(value.operands) != 0 { return "parameter type: " + f.symbol }
            }
            if value.op == "add" || value.op == "sub" || value.op == "mul" || value.op == "div" || value.op == "mod" {
                if value.type_name != "int" || len(value.operands) != 2 { return "binary value type: " + f.symbol }
                if ssa_value_type(f.blocks, value.operands[0]) != "int" || ssa_value_type(f.blocks, value.operands[1]) != "int" { return "binary operand type: " + f.symbol }
            }
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
        } else if block.terminator == "unreachable" {
            if len(block.successors) != 0 || len(block.terminator_values) != 0 { return "invalid unreachable terminator: " + f.symbol }
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
                    // A: phi's ith input is used on the ith incoming edge,
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
    record_error := ssa_records_error(program.records)
    if record_error != "" { return record_error }
    i := 0
    for i < len(program.functions) {
        if ssa_function_index(program.functions, program.functions[i].symbol) != i { return "duplicate function" }
        error := verify_ssa_function(program.functions[i])
        if error != "" { return error }
        f := program.functions[i]
        b := 0
        for b < len(f.blocks) {
            v := 0
            for v < len(f.blocks[b].values) {
                value := f.blocks[b].values[v]
                if value.op == "record_new" || value.op == "record_get" || value.op == "record_set" {
                    error = ssa_record_value_error(f, value, program.records)
                    if error != "" { return error }
                } else if value.op == "array_new" || value.op == "array_get" || value.op == "array_len" || value.op == "array_append" || value.op == "array_set" {
                    error = ssa_array_value_error(f, value, program.records)
                    if error != "" { return error }
                } else if len(value.field_names) != 0 { return "unexpected record field metadata" }
                v = v + 1
            }
            b = b + 1
        }
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
        // This: representation has one type per call value, so a call can
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

func ssa_record_value_error(function_ssa_function function_data, function_ssa_value value, function_ssa_record[] records) string {
    record_index := ssa_record_index(records, value.symbol)
    if record_index < 0 { return "SSA unknown record identity" }
    record := records[record_index]
    if value.op == "record_new" {
        if value.type_name != record.symbol || value.integer_value != 0 { return "SSA record constructor result type" }
        if len(value.field_names) != len(value.operands) { return "SSA record constructor field count" }
        i := 0
        for i < len(value.operands) {
            field := ssa_record_field_index(record, value.field_names[i])
            if field < 0 { return "SSA unknown record constructor field" }
            j := 0
            for j < i {
                if value.field_names[j] == value.field_names[i] { return "SSA duplicate record constructor field" }
                j = j + 1
            }
            if ssa_value_type(function_data.blocks, value.operands[i]) != record.field_types[field] { return "SSA record constructor field type" }
            i = i + 1
        }
        return ""
    }
    field := value.integer_value
    if len(value.field_names) != 0 || field < 0 || field >= len(record.field_types) { return "SSA record field index" }
    if value.op == "record_set" {
        if len(value.operands) != 2 || value.type_name != record.symbol { return "SSA record store result type or arity" }
        if ssa_value_type(function_data.blocks, value.operands[1]) != record.field_types[field] { return "SSA record store field type" }
    } else if len(value.operands) != 1 || value.type_name != record.field_types[field] { return "SSA record projection result type or arity" }
    if ssa_value_type(function_data.blocks, value.operands[0]) != record.symbol { return "SSA record target type" }
    return ""
}

func ssa_record_index(function_ssa_record[] records, string symbol) int {
    i := 0
    for i < len(records) {
        if records[i].symbol == symbol { return i }
        i = i + 1
    }
    return -1
}

func ssa_record_field_index(function_ssa_record record, string name) int {
    i := 0
    for i < len(record.field_names) {
        if record.field_names[i] == name { return i }
        i = i + 1
    }
    return -1
}

func ssa_records_error(function_ssa_record[] records) string {
    i := 0
    for i < len(records) {
        record := records[i]
        if record.symbol == "" || ssa_record_index(records, record.symbol) != i { return "SSA invalid or duplicate record identity" }
        if len(record.field_names) != len(record.field_types) { return "SSA record field count" }
        f := 0
        for f < len(record.field_names) {
            if record.field_names[f] == "" || ssa_record_field_index(record, record.field_names[f]) != f { return "SSA invalid or duplicate record field" }
            field_type := record.field_types[f]
            if !ssa_type_supported(field_type, records) { return "SSA unsupported record field type" }
            f = f + 1
        }
        i = i + 1
    }
    return ""
}

func ssa_array_element(string type_name) string {
    if len(type_name) > 2 && __host_slice(type_name, 0, 2) == "[]" { return __host_slice(type_name, 2, len(type_name)) }
    if len(type_name) > 2 && __host_slice(type_name, len(type_name) - 2, len(type_name)) == "[]" { return __host_slice(type_name, 0, len(type_name) - 2) }
    return ""
}

func ssa_type_supported(string type_name, function_ssa_record[] records) bool {
    if type_name == "int" || type_name == "()" || type_name == "bool" || ssa_record_index(records, type_name) >= 0 { return true }
    element := ssa_array_element(type_name)
    if element != "" { return ssa_type_supported(element, records) }
    return false
}

func ssa_array_value_error(function_ssa_function function_data, function_ssa_value value, function_ssa_record[] records) string {
    element := ssa_array_element(value.symbol)
    if element == "" || !ssa_type_supported(element, records) { return "SSA unknown array element type" }
    if len(value.field_names) != 0 || value.integer_value != 0 { return "SSA invalid array metadata" }
    if value.op == "array_new" {
        if value.type_name != value.symbol { return "SSA array constructor result type" }
        i := 0
        for i < len(value.operands) {
            if ssa_value_type(function_data.blocks, value.operands[i]) != element { return "SSA array constructor element type" }
            i = i + 1
        }
        return ""
    }
    if len(value.operands) < 1 || ssa_value_type(function_data.blocks, value.operands[0]) != value.symbol { return "SSA array target type" }
    if value.op == "array_len" {
        if len(value.operands) != 1 || value.type_name != "int" { return "SSA array length type or arity" }
        return ""
    }
    if value.op == "array_set" {
        if len(value.operands) != 3 || value.type_name != value.symbol { return "SSA array store result type or arity" }
        if ssa_value_type(function_data.blocks, value.operands[1]) != "int" || ssa_value_type(function_data.blocks, value.operands[2]) != element { return "SSA array store index or element type" }
        return ""
    }
    if len(value.operands) != 2 { return "SSA array operation arity" }
    if value.op == "array_get" {
        if ssa_value_type(function_data.blocks, value.operands[1]) != "int" || value.type_name != element { return "SSA array index or result type" }
        return ""
    }
    if ssa_value_type(function_data.blocks, value.operands[1]) != element || value.type_name != value.symbol { return "SSA array append element or result type" }
    return ""
}

func ssa_is_scalar_operation(string op) bool {
    return op == "const_bool" || op == "bool_to_int" || op == "cmp_eq" || op == "cmp_ne" || op == "cmp_lt" || op == "cmp_le" || op == "cmp_gt" || op == "cmp_ge"
}

func ssa_scalar_value_error(function_ssa_function function_data, function_ssa_value value) string {
    if value.op == "const_bool" {
        if value.type_name != "bool" || len(value.operands) != 0 || (value.integer_value != 0 && value.integer_value != 1) { return "SSA invalid bool constant" }
        return ""
    }
    if value.op == "bool_to_int" {
        if value.type_name != "int" || len(value.operands) != 1 { return "SSA invalid bool conversion" }
        if ssa_value_type(function_data.blocks, value.operands[0]) != "bool" { return "SSA bool conversion source type" }
        return ""
    }
    if value.type_name != "bool" || len(value.operands) != 2 { return "SSA comparison result type or arity" }
    left := ssa_value_type(function_data.blocks, value.operands[0])
    right := ssa_value_type(function_data.blocks, value.operands[1])
    if left != right { return "SSA comparison operand type mismatch" }
    if value.op == "cmp_eq" || value.op == "cmp_ne" {
        if left != "int" && left != "bool" { return "SSA comparison requires scalar operands" }
    } else if left != "int" { return "SSA ordered comparison requires int operands" }
    return ""
}
