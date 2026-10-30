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

struct function_ssa_global {
    string symbol
    string type_name
    string initializer
}

struct function_ssa_program {
    function_ssa_global[] globals
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

// Run only after validating the complete unit. Executables retain the entry,
// every global initializer, and their transitive direct-call closure. Keep the
// original function order so emission remains deterministic.
func ssa_executable_program(function_ssa_program original) function_ssa_program {
    live := int[]()
    i := 0
    for i < len(original.functions) { live.push(0); i = i + 1 }
    entry := original.entry_symbol
    pending := [entry];
    g := 0
    for g < len(original.globals) {
        if original.globals[g].initializer != "" { pending.push(original.globals[g].initializer) }
        g = g + 1
    }
    cursor := 0
    for cursor < len(pending) {
        symbol := pending[cursor]; cursor = cursor + 1
        index := ssa_function_index(original.functions, symbol)
        if index >= 0 && live[index] == 0 {
            live[index] = 1
            c := 0
            for c < len(original.calls) {
                edge := original.calls[c]
                if edge.caller == symbol { pending.push(edge.callee) }
                c = c + 1
            }
        }
    }
    functions := function_ssa_function[]()
    i = 0
    for i < len(original.functions) {
        if live[i] != 0 { functions.push(original.functions[i]) }
        i = i + 1
    }
    calls := function_ssa_call[]()
    i = 0
    for i < len(original.calls) {
        edge := original.calls[i]
        index := ssa_function_index(original.functions, edge.caller)
        if index >= 0 && live[index] != 0 { calls.push(edge) }
        i = i + 1
    }
    return function_ssa_program { globals: original.globals, records: original.records,
        package_name: original.package_name, entry_symbol: original.entry_symbol,
        functions: functions, calls: calls }
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

// Bodyless declarations use sentinel block identities; definitions always have an entry.
func ssa_function_external(function_ssa_function f) bool {
    return f.entry_block == -1 && f.exit_block == -1 && len(f.blocks) == 0
}

func verify_ssa_function(function_ssa_function f) string {
    if f.symbol == "" { return "empty function symbol" }
    t := 0
    for t < len(f.parameter_types) {
        if f.parameter_types[t] == "" { return "empty parameter type: " + f.symbol }
        t = t + 1
    }
    t = 0
    for t < len(f.result_types) {
        if f.result_types[t] == "" { return "empty result type: " + f.symbol }
        if mir_program_contains_reference(f.result_types[t]) { return "SSA reference result escapes its call" }
        t = t + 1
    }
    if f.entry_block == -1 {
        if len(f.blocks) != 0 || f.entry_block != -1 || f.exit_block != -1 { return "invalid external declaration: " + f.symbol }
        return ""
    }
    if len(f.blocks) == 0 { return "function has no blocks: " + f.symbol }
    if ssa_block_index(f.blocks, f.entry_block) < 0 { return "missing entry block: " + f.symbol }
    if f.exit_block >= 0 && ssa_block_index(f.blocks, f.exit_block) < 0 { return "missing exit block: " + f.symbol }
    if len(f.blocks[ssa_block_index(f.blocks, f.entry_block)].predecessors) != 0 { return "entry block has predecessors: " + f.symbol }
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
            if value.op == "native_intrinsic" {
                intrinsic_error := ssa_native_intrinsic_error(f, value)
                if intrinsic_error != "" { return intrinsic_error }
            }
            if ssa_is_scalar_operation(value.op) {
                scalar_error := ssa_scalar_value_error(f, value)
                if scalar_error != "" { return scalar_error }
            }
            if value.op == "const_string" || value.op == "string_concat" || value.op == "string_byte_at" || value.op == "string_char_at" || value.op == "string_slice" || value.op == "string_len" || value.op == "string_eq" || value.op == "string_ne" || value.op == "string_lt" || value.op == "string_le" || value.op == "string_gt" || value.op == "string_ge" {
                string_error := ssa_string_value_error(f, value)
                if string_error != "" { return string_error }
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
            if value.op == "phi" && (len(value.operands) == 0 || len(value.operands) != len(block.predecessors)) { return "phi operand count: " + f.symbol }
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
    if ssa_function_external(program.functions[ssa_function_index(program.functions, program.entry_symbol)]) { return "entry function is external" }
    record_error := ssa_records_error(program.records)
    if record_error != "" { return record_error }
    global_error := ssa_globals_error(program)
    if global_error != "" { return global_error }
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
                if mir_program_reference_element(value.type_name) != "" && value.op != "param" && value.op != "reference_new" && value.op != "reference_readonly" { return "SSA unproven reference result" }
                a := 0
                for a < len(value.operands) {
                    if mir_program_reference_element(ssa_value_type(f.blocks, value.operands[a])) != "" && value.op != "reference_get" && value.op != "reference_set" && value.op != "reference_readonly" && value.op != "call" { return "SSA reference used outside a proven borrow operation" }
                    a = a + 1
                }
                if value.op == "global_get" || value.op == "global_set" {
                    error = ssa_global_value_error(f, value, program.globals)
                    if error != "" { return error }
                } else if value.op == "reference_new" || value.op == "reference_get" || value.op == "reference_set" || value.op == "reference_readonly" {
                    error = ssa_reference_value_error(f, value, program.records)
                    if error != "" { return error }
                } else if value.op == "record_new" || value.op == "record_get" || value.op == "record_set" {
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
            if mir_program_reference_element(target.parameter_types[a]) != "" {
                previous := 0
                for previous < a {
                    if mir_program_reference_element(target.parameter_types[previous]) != "" && ssa_reference_origin(program.functions[caller], value.operands[previous]) == ssa_reference_origin(program.functions[caller], value.operands[a])
                        && (mir_program_reference_mutable(target.parameter_types[previous]) || mir_program_reference_mutable(target.parameter_types[a])) { return "SSA aliased mutable call reference" }
                    previous = previous + 1
                }
            }
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
    order := ssa_global_order(program)
    if order.error != "" { return order.error }
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
    referent := mir_program_reference_element(type_name)
    if referent != "" { return ssa_record_index(records, referent) >= 0 || (ssa_array_element(referent) != "" && ssa_type_supported(referent, records)) }
    if type_name == "string" || type_name == "int" || type_name == "()" || type_name == "bool" || ssa_record_index(records, type_name) >= 0 { return true }
    element := ssa_array_element(type_name)
    if element != "" { return ssa_type_supported(element, records) }
    return false
}

func ssa_reference_origin(function_ssa_function function_data, int original) int {
    id := original
    remaining := 1
    b := 0
    for b < len(function_data.blocks) { remaining = remaining + len(function_data.blocks[b].values); b = b + 1 }
    for remaining > 0 {
        defining := ssa_value_block_index(function_data.blocks, id)
        if defining < 0 { return -1 }
        value := function_data.blocks[defining].values[ssa_value_index(function_data.blocks[defining].values, id)]
        if value.op != "reference_readonly" || len(value.operands) != 1 { return id }
        id = value.operands[0]; remaining = remaining - 1
    }
    return -1
}

func ssa_reference_value_error(function_ssa_function function_data, function_ssa_value value, function_ssa_record[] records) string {
    if len(value.field_names) != 0 || value.integer_value != 0 || value.symbol == "" || !ssa_type_supported("&" + value.symbol, records) { return "SSA invalid reference metadata" }
    if value.op == "reference_new" {
        if len(value.operands) != 1 || mir_program_reference_element(value.type_name) != value.symbol { return "SSA reference allocation result type or arity" }
        if ssa_value_type(function_data.blocks, value.operands[0]) != value.symbol { return "SSA reference allocation value type" }
        return ""
    }
    if len(value.operands) < 1 { return "SSA missing reference operand" }
    reference_type := ssa_value_type(function_data.blocks, value.operands[0])
    if mir_program_reference_element(reference_type) != value.symbol { return "SSA reference operand referent type" }
    if value.op == "reference_set" {
        if !mir_program_reference_mutable(reference_type) || len(value.operands) != 2 || value.type_name != "()" { return "SSA readonly reference store or invalid arity" }
        if ssa_value_type(function_data.blocks, value.operands[1]) != value.symbol { return "SSA reference store value type" }
    } else if value.op == "reference_readonly" {
        if len(value.operands) != 1 || value.type_name != "&" + value.symbol { return "SSA invalid readonly reborrow" }
    } else if len(value.operands) != 1 || value.type_name != value.symbol { return "SSA reference load result type or arity" }
    return ""
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

func ssa_string_value_error(function_ssa_function f, function_ssa_value value) string {
    if len(value.field_names) != 0 || value.integer_value != 0 { return "SSA invalid string metadata" }
    if value.op == "const_string" {
        if len(value.operands) != 0 || value.type_name != "string" { return "SSA invalid string constant" }
        return ""
    }
    if value.symbol != "" { return "SSA unexpected string symbol" }
    if value.op == "string_byte_at" || value.op == "string_char_at" || value.op == "string_slice" {
        count := 2
        result := "string"
        if value.op == "string_slice" { count = 3 }
        if value.op == "string_byte_at" { result = "int" }
        if len(value.operands) != count || value.type_name != result { return "string access count or result type" }
        if ssa_value_type(f.blocks, value.operands[0]) != "string" { return "string access target type" }
        i := 1
        for i < count {
            if ssa_value_type(f.blocks, value.operands[i]) != "int" { return "string access index type" }
            i = i + 1
        }
        return ""
    }
    count := 2
    result := "string"
    if value.op == "string_eq" || value.op == "string_ne" || value.op == "string_lt" || value.op == "string_le" || value.op == "string_gt" || value.op == "string_ge" { result = "bool" }
    if value.op == "string_len" { count = 1; result = "int" }
    if len(value.operands) != count || value.type_name != result { return "SSA string operand count or result type" }
    i := 0
    for i < count {
        if ssa_value_type(f.blocks, value.operands[i]) != "string" { return "SSA string operand type" }
        i = i + 1
    }
    return ""
}

// Exact signatures form the native runtime boundary; names never become assembler symbols.
func ssa_native_intrinsic_result(string name) string {
    if name == "__host_env_get" { return "string" }
    if name == "__host_run_argv" { return "int" }
    if name == "__host_same_file" { return "bool" }
    if name == "__host_rename_file" { return "int" }
    if name == "__host_make_temp_dir_in" { return "string" }
    if name == "__host_make_executable" { return "int" }
    if name == "host_args" { return "string[]" }
    if name == "__host_read_to_string" { return "string" }
    if name == "__host_read_source" { return "string" }
    if name == "__host_write_text_file" { return "int" }
    if name == "runtime_env_get" { return "string" }
    if name == "eprintln" { return "void" }
    if name == "println" { return "void" }
    if name == "panic" { return "void" }
    if name == "__int_to_string" { return "string" }
    if name == "__host_byte_at" { return "int" }
    if name == "__host_char_at" { return "string" }
    if name == "__host_slice" { return "string" }
    if name == "__string_char_at" { return "string" }
    if name == "__string_slice" { return "string" }
    return "?"
}
func ssa_native_intrinsic_parameters(string name) string[] {
    if name == "__host_env_get" { return ["string"] }
    if name == "__host_run_argv" { return ["string[]"] }
    if name == "__host_same_file" { return ["string","string"] }
    if name == "__host_rename_file" { return ["string","string"] }
    if name == "__host_make_temp_dir_in" { return ["string"] }
    if name == "__host_make_executable" { return ["string"] }
    if name == "host_args" { return string[]() }
    if name == "__host_read_to_string" { return ["string"] }
    if name == "__host_read_source" { return ["string"] }
    if name == "__host_write_text_file" { return ["string","string"] }
    if name == "runtime_env_get" { return ["string","string"] }
    if name == "eprintln" { return ["string"] }
    if name == "println" { return ["string"] }
    if name == "panic" { return ["string"] }
    if name == "__int_to_string" { return ["int"] }
    if name == "__host_byte_at" { return ["string","int"] }
    if name == "__host_char_at" { return ["string","int"] }
    if name == "__host_slice" { return ["string","int","int"] }
    if name == "__string_char_at" { return ["string","int"] }
    if name == "__string_slice" { return ["string","int","int"] }
    return string[]()
}
func ssa_native_intrinsic_error(function_ssa_function f, function_ssa_value value) string {
    result := ssa_native_intrinsic_result(value.symbol)
    if result == "?" { return "SSA unknown native intrinsic: " + value.symbol }
    params := ssa_native_intrinsic_parameters(value.symbol)
    if len(value.field_names) != 0 || value.integer_value != 0 { return "SSA invalid native intrinsic metadata" }
    if len(value.operands) != len(params) || value.type_name != result { return "SSA native intrinsic signature" }
    i := 0
    for i < len(params) {
        if ssa_value_type(f.blocks, value.operands[i]) != params[i] { return "SSA native intrinsic argument type" }
        i = i + 1
    }
    return ""
}

func ssa_global_index(function_ssa_global[] globals, string symbol) int {
    i := 0
    for i < len(globals) {
        if globals[i].symbol == symbol { return i }
        i = i + 1
    }
    return -1
}
func ssa_global_value_error(function_ssa_function f, function_ssa_value value, function_ssa_global[] globals) string {
    if value.op != "global_get" && value.op != "global_set" { return "SSA unknown global operation" }
    index := ssa_global_index(globals, value.symbol)
    if index < 0 { return "SSA unknown global: " + value.symbol }
    if len(value.field_names) != 0 || value.integer_value != 0 { return "SSA invalid global instruction metadata" }
    type_name := globals[index].type_name
    if value.op == "global_get" {
        if len(value.operands) != 0 || value.type_name != type_name { return "SSA global load type or arity" }
    } else {
        if len(value.operands) != 1 || value.type_name != "()" { return "SSA global store result type or arity" }
        if ssa_value_type(f.blocks, value.operands[0]) != type_name { return "SSA global store operand type" }
    }
    return ""
}
func ssa_globals_error(function_ssa_program program) string {
    i := 0
    for i < len(program.globals) {
        global := program.globals[i]
        if global.symbol == "" || ssa_global_index(program.globals, global.symbol) != i { return "SSA invalid or duplicate global identity" }
        if !ssa_type_supported(global.type_name, program.records) { return "SSA unsupported global type" }
        if global.initializer != "" {
            target := ssa_function_index(program.functions, global.initializer)
            if target < 0 { return "SSA unknown global initializer" }
            function := program.functions[target]
            if len(function.parameter_types) != 0 || len(function.result_types) != 1 { return "SSA global initializer signature" }
            if function.result_types[0] != global.type_name { return "SSA global initializer result type" }
        }
        i = i + 1
    }
    return ""
}
struct ssa_global_order_result { int[] order; string error }
func ssa_global_dependencies(function_ssa_program program, int root) int[] {
    globals := program.globals
    functions := program.functions
    dependencies := int[]()
    g := 0
    for g < len(globals) { dependencies.push(0); g = g + 1 }
    visited := int[]()
    f := 0
    for f < len(functions) { visited.push(0); f = f + 1 }
    pending := [root];
    cursor := 0
    for cursor < len(pending) {
        index := pending[cursor]
        if visited[index] == 0 {
            visited[index] = 1
            function := functions[index]
            b := 0
            for b < len(function.blocks) {
                i := 0
                for i < len(function.blocks[b].values) {
                    ins := function.blocks[b].values[i]
                    if ins.op == "global_get" || ins.op == "global_set" {
                        target := ssa_global_index(globals, ins.symbol)
                        if target >= 0 { dependencies[target] = 1 }
                    }
                    if ins.op == "call" {
                        c := 0
                        for c < len(program.calls) {
                            edge := program.calls[c]
                            if edge.caller == function.symbol && edge.block_id == function.blocks[b].id && edge.value_id == ins.id {
                                target := ssa_function_index(functions, edge.callee)
                                if target >= 0 && visited[target] == 0 { pending.push(target) }
                            }
                            c = c + 1
                        }
                    }
                    i = i + 1
                }
                b = b + 1
            }
        }
        cursor = cursor + 1
    }
    return dependencies
}
func ssa_global_order(function_ssa_program program) ssa_global_order_result {
    globals := program.globals
    functions := program.functions
    order := int[]()
    done := int[]()
    g := 0
    for g < len(globals) { done.push(0); g = g + 1 }
    for len(order) < len(globals) {
        progress := false
        g = 0
        for g < len(globals) {
            if done[g] == 0 {
                ready := true
                if globals[g].initializer != "" {
                    root := ssa_function_index(functions, globals[g].initializer)
                    if root < 0 { return ssa_global_order_result { order: order, error: "unknown global initializer" } }
                    dependencies := ssa_global_dependencies(program, root)
                    d := 0
                    for d < len(dependencies) {
                        if dependencies[d] != 0 && done[d] == 0 { ready = false }
                        d = d + 1
                    }
                }
                if ready { done[g] = 1; order.push(g); progress = true }
            }
            g = g + 1
        }
        if !progress { return ssa_global_order_result { order: order, error: "cyclic global initialization" } }
    }
    return ssa_global_order_result { order: order, error: "" }
}
