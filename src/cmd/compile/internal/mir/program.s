package compile.internal

extern "intrinsic" func __host_slice(string text, int start, int end) string


// Executable: module boundary. IDs: are local to a function, symbols to a package.
// Physical value layout and native calling convention belong to later lowering.
struct mir_program_parameter {
    int value_id
    string name
    string type_name
}

struct mir_program_record {
    string symbol
    string[] field_names
    string[] field_types
}

struct mir_program_instruction {
    string[] field_names
    string op
    int[] result_ids
    string[] result_types
    int[] operands
    int integer_value
    string symbol
}

struct mir_program_block {
    int[] successors
    int id
    mir_program_instruction[] instructions
    string terminator
    int[] return_values
}

struct mir_program_function {
    string symbol
    mir_program_parameter[] params
    string[] result_types
    mir_program_block[] blocks
    bool external
}

struct mir_program_call {
    string caller
    string callee
    int block_id
    int instruction_index
}

struct mir_program_global {
    string symbol
    string type_name
    string initializer
}

struct mir_program {
    mir_program_global[] globals
    mir_program_record[] records
    mir_program_enum[] enums
    string package_name
    string entry_symbol
    mir_program_function[] functions
    mir_program_call[] calls
}

struct mir_program_result {
    mir_program program
    string error
}

func mir_program_function_index(mir_program_function[] functions, string symbol) int {
    i := 0
    for i < len(functions) {
        if functions[i].symbol == symbol { return i }
        i = i + 1
    }
    return -1
}

// Only values defined before the current instruction are available in P1's
// straight-line blocks. No expression is evaluated to construct the module.
func mir_program_value_type(mir_program_function function_data, int id, int limit) string {
    i := 0
    for i < len(function_data.params) {
        if function_data.params[i].value_id == id { return function_data.params[i].type_name }
        i = i + 1
    }
    b := 0
    for b < len(function_data.blocks) {
        i = 0
        for i < len(function_data.blocks[b].instructions) {
            if len(function_data.blocks) == 1 && i >= limit { break }
            ins := function_data.blocks[b].instructions[i]
            r := 0
            for r < len(ins.result_ids) {
                if ins.result_ids[r] == id { return ins.result_types[r] }
                r = r + 1
            }
            i = i + 1
        }
        b = b + 1
    }
    return ""
}

func mir_program_instruction_error_with_globals(mir_program_function function_data, mir_program_function[] functions, mir_program_instruction ins, int index, mir_program_enum[] enums, mir_program_record[] records, mir_program_global[] globals) string {
    if len(ins.result_ids) != len(ins.result_types) { return "result type count in: " + function_data.symbol }
    r := 0
    for r < len(ins.result_ids) {
        if ins.result_ids[r] < 0 || ins.result_types[r] == "" { return "invalid value in: " + function_data.symbol }
        if len(function_data.blocks) == 1 && mir_program_value_type(function_data, ins.result_ids[r], index) != "" { return "duplicate value in: " + function_data.symbol }
        previous := 0
        for previous < r {
            previous_id := ins.result_ids[previous]
            current_id := ins.result_ids[r]
            if previous_id == current_id { return "duplicate value in: " + function_data.symbol }
            previous = previous + 1
        }
        r = r + 1
    }
    a := 0
    for a < len(ins.operands) {
        if mir_program_value_type(function_data, ins.operands[a], index) == "" { return "undefined value in: " + function_data.symbol }
        if mir_program_reference_element(mir_program_value_type(function_data, ins.operands[a], index)) != "" && ins.op != "reference_get" && ins.op != "reference_set" && ins.op != "reference_readonly" && ins.op != "call" { return "reference used outside a proven borrow operation" }
        a = a + 1
    }
    r = 0
    for r < len(ins.result_types) {
        if mir_program_reference_element(ins.result_types[r]) != "" && ins.op != "reference_new" && ins.op != "reference_readonly" { return "unproven reference result" }
        r = r + 1
    }
    if ins.op == "reference_new" || ins.op == "reference_get" || ins.op == "reference_set" || ins.op == "reference_readonly" { return mir_program_reference_instruction_error(function_data, ins, index, records, enums) }
    if ins.op == "global_get" || ins.op == "global_set" { return mir_program_global_instruction_error(function_data, ins, index, globals) }
    if ins.op == "native_intrinsic" { return mir_native_intrinsic_error(function_data, ins, index) }
    if ins.op == "call" {
        target := mir_program_function_index(functions, ins.symbol)
        if target < 0 { return "unknown callee: " + ins.symbol }
        callee := functions[target]
        if len(ins.operands) != len(callee.params) { return "call argument count: " + ins.symbol }
        if len(ins.result_types) != len(callee.result_types) { return "call result count: " + ins.symbol }
        a = 0
        for a < len(ins.operands) {
            if mir_program_value_type(function_data, ins.operands[a], index) != callee.params[a].type_name {
                return "call argument type: " + ins.symbol
            }
            if mir_program_reference_element(callee.params[a].type_name) != "" {
                previous := 0
                for previous < a {
                    if mir_program_reference_element(callee.params[previous].type_name) != "" && mir_program_reference_origin(function_data, ins.operands[previous]) == mir_program_reference_origin(function_data, ins.operands[a])
                        && (mir_program_reference_mutable(callee.params[previous].type_name) || mir_program_reference_mutable(callee.params[a].type_name)) { return "aliased mutable call reference" }
                    previous = previous + 1
                }
            }
            a = a + 1
        }
        r = 0
        for r < len(ins.result_types) {
            result_type := ins.result_types[r]
            callee_result_type := callee.result_types[r]
            if result_type != callee_result_type { return "call result type: " + ins.symbol }
            r = r + 1
        }
        return ""
    }
    if len(ins.result_ids) != 1 { return "instruction result count: " + ins.op }
    if ins.op == "const_string" || ins.op == "string_concat" || ins.op == "string_byte_at" || ins.op == "string_char_at" || ins.op == "string_slice" || ins.op == "string_len" || ins.op == "string_eq" || ins.op == "string_ne" || ins.op == "string_lt" || ins.op == "string_le" || ins.op == "string_gt" || ins.op == "string_ge" { return mir_program_string_instruction_error(function_data, ins, index) }
    if ins.op == "array_new" || ins.op == "array_get" || ins.op == "array_len" || ins.op == "array_append" || ins.op == "array_set" { return mir_program_array_instruction_error(function_data, ins, index, records, enums) }
    if ins.op == "record_new" || ins.op == "record_get" || ins.op == "record_set" { return mir_program_record_instruction_error(function_data, ins, index, records) }
    if len(ins.field_names) != 0 { return "unexpected record field metadata: " + ins.op }
    if ins.op == "const_bool" || ins.op == "bool_to_int" || ins.op == "cmp_eq" || ins.op == "cmp_ne" || ins.op == "cmp_lt" || ins.op == "cmp_le" || ins.op == "cmp_gt" || ins.op == "cmp_ge" { return mir_program_scalar_instruction_error(function_data, ins, index, enums) }
    if ins.op == "const_enum" || ins.op == "enum_to_int" { return mir_program_enum_instruction_error(function_data, ins, index, enums) }
    if ins.op == "phi" {
        if len(ins.operands) == 0 { return "phi requires incoming values" }
        a = 0
        for a < len(ins.operands) {
            if mir_program_value_type(function_data, ins.operands[a], index) != ins.result_types[0] { return "phi operand type" }
            a = a + 1
        }
        return ""
    }
    if ins.op == "const_int" {
        if len(ins.operands) != 0 || ins.result_types[0] != "int" { return "invalid integer constant" }
        return ""
    }
    if ins.op == "const_unit" {
        if len(ins.operands) != 0 || ins.result_types[0] != "()" || ins.integer_value != 0 { return "invalid unit constant" }
        return ""
    }
    if ins.op == "copy" {
        if len(ins.operands) != 1 { return "copy operand count" }
        if ins.result_types[0] != mir_program_value_type(function_data, ins.operands[0], index) { return "copy type mismatch" }
        return ""
    }
    if ins.op == "add" || ins.op == "sub" || ins.op == "mul" || ins.op == "div" || ins.op == "mod" {
        if len(ins.operands) != 2 { return "binary operand count: " + ins.op }
        if ins.result_types[0] != "int" { return "binary result type: " + ins.op }
        if mir_program_value_type(function_data, ins.operands[0], index) != "int" || mir_program_value_type(function_data, ins.operands[1], index) != "int" {
            return "binary operand type: " + ins.op
        }
        return ""
    }
    return "unsupported instruction: " + ins.op
}

func mir_program_function_error_with_globals(mir_program_function function_data, mir_program_function[] functions, mir_program_enum[] enums, mir_program_record[] records, mir_program_global[] globals) string {
    if function_data.symbol == "" { return "empty function symbol" }
    p := 0
    for p < len(function_data.params) {
        if function_data.params[p].value_id < 0 || function_data.params[p].name == "" || function_data.params[p].type_name == "" { return "invalid parameter: " + function_data.symbol }
        if mir_program_reference_element(function_data.params[p].type_name) != "" && (!mir_program_type_supported(function_data.params[p].type_name, records, enums) || function_data.external) { return "unproven reference parameter" }
        previous := 0
        for previous < p {
            if function_data.params[previous].value_id == function_data.params[p].value_id { return "duplicate parameter value: " + function_data.symbol }
            if function_data.params[previous].name == function_data.params[p].name { return "duplicate parameter name: " + function_data.symbol }
            previous = previous + 1
        }
        p = p + 1
    }
    p = 0
    for p < len(function_data.result_types) {
        if function_data.result_types[p] == "" { return "empty result type: " + function_data.symbol }
        if mir_program_reference_element(function_data.result_types[p]) != "" { return "reference result escapes its call" }
        p = p + 1
    }
    if function_data.external {
        if len(function_data.blocks) != 0 { return "external function has body: " + function_data.symbol }
        return ""
    }
    if len(function_data.blocks) == 0 { return "function has no blocks: " + function_data.symbol }
    entry := function_data.blocks[0].id
    if len(mir_program_predecessors(function_data, entry)) != 0 { return "entry block has predecessors" }
    b := 0
    for b < len(function_data.blocks) {
        block := function_data.blocks[b]
        if block.id < 0 || mir_program_block_index(function_data, block.id) != b { return "invalid or duplicate block" }
        e := 0
        for e < len(block.successors) {
            if mir_program_block_index(function_data, block.successors[e]) < 0 { return "unknown successor block" }
            e = e + 1
        }
        predecessors := mir_program_predecessors(function_data, block.id)
        non_phi := false
        i := 0
        for i < len(block.instructions) {
            ins := block.instructions[i]
            if ins.op == "phi" {
                if non_phi || len(ins.operands) != len(predecessors) { return "phi position or predecessor count" }
            } else { non_phi = true }
            r := 0
            for r < len(ins.result_ids) {
                if mir_program_value_definition_count(function_data, ins.result_ids[r]) != 1 { return "duplicate value in: " + function_data.symbol }
                r = r + 1
            }
            error := mir_program_instruction_error_with_globals(function_data, functions, ins, i, enums, records, globals)
            if error != "" { return error }
            i = i + 1
        }
        if block.terminator == "return" {
            if len(block.successors) != 0 || len(block.return_values) != len(function_data.result_types) { return "return count or successors" }
        } else if block.terminator == "jump" {
            if len(block.successors) != 1 || len(block.return_values) != 0 { return "invalid jump" }
        } else if block.terminator == "branch" {
            if len(block.successors) != 2 || len(block.return_values) != 1 { return "invalid branch" }
        } else if block.terminator == "unreachable" {
            if len(block.successors) != 0 || len(block.return_values) != 0 { return "invalid unreachable terminator" }
        } else { return "unsupported terminator: " + block.terminator }
        i = 0
        for i < len(block.return_values) {
            actual := mir_program_value_type(function_data, block.return_values[i], len(block.instructions))
            if actual == "" { return "undefined terminator value" }
            if block.terminator == "return" && actual != function_data.result_types[i] { return "return type: " + function_data.symbol }
            if block.terminator == "branch" && actual != "bool" { return "branch condition type" }
            i = i + 1
        }
        b = b + 1
    }
    dominance := mir_program_dominance_matrix(function_data)
    b = 0
    for b < len(function_data.blocks) {
        block := function_data.blocks[b]
        predecessors := mir_program_predecessors(function_data, block.id)
        i := 0
        for i < len(block.instructions) {
            ins := block.instructions[i]
            a := 0
            for a < len(ins.operands) {
                use_block := b
                use_position := i
                if ins.op == "phi" {
                    use_block = mir_program_block_index(function_data, predecessors[a])
                    use_position = len(function_data.blocks[use_block].instructions)
                }
                error := mir_program_value_use_error(function_data, dominance, ins.operands[a], use_block, use_position)
                if error != "" { return error }
                a = a + 1
            }
            i = i + 1
        }
        i = 0
        for i < len(block.return_values) {
            error := mir_program_value_use_error(function_data, dominance, block.return_values[i], b, len(block.instructions))
            if error != "" { return error }
            i = i + 1
        }
        b = b + 1
    }
    return ""
}

func mir_program_block_index(mir_program_function function_data, int id) int {
    i := 0
    for i < len(function_data.blocks) { if function_data.blocks[i].id == id { return i }
        i = i + 1
    }
    return -1
}

func mir_program_predecessors(mir_program_function function_data, int id) int[] {
    predecessors := int[]()
    b := 0
    for b < len(function_data.blocks) {
        e := 0
        for e < len(function_data.blocks[b].successors) {
            if function_data.blocks[b].successors[e] == id { predecessors = append(predecessors, function_data.blocks[b].id) }
            e = e + 1
        }
        b = b + 1
    }
    return predecessors
}

func mir_program_value_definition_count(mir_program_function function_data, int id) int {
    count := 0
    p := 0
    for p < len(function_data.params) { if function_data.params[p].value_id == id { count = count + 1 }
        p = p + 1
    }
    b := 0
    for b < len(function_data.blocks) {
        i := 0
        for i < len(function_data.blocks[b].instructions) {
            r := 0
            for r < len(function_data.blocks[b].instructions[i].result_ids) {
                if function_data.blocks[b].instructions[i].result_ids[r] == id { count = count + 1 }
                r = r + 1
            }
            i = i + 1
        }
        b = b + 1
    }
    return count
}

func mir_program_reachable_blocks(mir_program_function function_data, int excluded) int[] {
    reachable := int[]()
    i := 0
    for i < len(function_data.blocks) { reachable = append(reachable, 0); i = i + 1 }
    if excluded == 0 { return reachable }
    pending := int[]{0}
    reachable[0] = 1
    i = 0
    for i < len(pending) {
        block := function_data.blocks[pending[i]]
        e := 0
        for e < len(block.successors) {
            next := mir_program_block_index(function_data, block.successors[e])
            if next != excluded && reachable[next] == 0 { reachable[next] = 1; pending = append(pending, next) }
            e = e + 1
        }
        i = i + 1
    }
    return reachable
}

func mir_program_dominance_matrix(mir_program_function function_data) int[] {
    reachable := mir_program_reachable_blocks(function_data, -1)
    dominance := int[]()
    d := 0
    for d < len(function_data.blocks) {
        without := mir_program_reachable_blocks(function_data, d)
        u := 0
        for u < len(function_data.blocks) {
            value := 0
            if reachable[u] == 0 || d == u || without[u] == 0 { value = 1 }
            dominance = append(dominance, value)
            u = u + 1
        }
        d = d + 1
    }
    return dominance
}

func mir_program_value_use_error(mir_program_function function_data, int[] dominance, int id, int use_block, int use_position) string {
    p := 0
    for p < len(function_data.params) { if function_data.params[p].value_id == id { return "" }
        p = p + 1
    }
    b := 0
    for b < len(function_data.blocks) {
        i := 0
        for i < len(function_data.blocks[b].instructions) {
            ids := function_data.blocks[b].instructions[i].result_ids
            r := 0
            for r < len(ids) {
                if ids[r] == id {
                    if b == use_block && i >= use_position { return "forward MIR operand" }
                    if dominance[b * len(function_data.blocks) + use_block] == 0 { return "nondominating MIR operand" }
                    return ""
                }
                r = r + 1
            }
            i = i + 1
        }
        b = b + 1
    }
    return "undefined MIR operand"
}

func mir_program_append_call(mir_program_call[] calls, string caller, string callee, int block_id, int instruction_index) mir_program_call[] {
    calls.push(mir_program_call {
        caller: caller, callee: callee, block_id: block_id, instruction_index: instruction_index,
    })
    return calls
}

func lower_mir_program_with_globals(string package_name, string entry_symbol, mir_program_function[] functions, mir_program_enum[] enums, mir_program_record[] records, mir_program_global[] globals) mir_program_result {
    empty := mir_program {
        package_name: package_name, entry_symbol: entry_symbol,
        functions: mir_program_function[]{}, calls: mir_program_call[]{},
    }
    result := mir_program_result { program: empty, error: mir_program_enums_error(enums) }
    if result.error != "" { return result }
    result.error = mir_program_records_error(records, enums)
    if result.error != "" { return result }
    result.error = mir_program_globals_error(globals, functions, records, enums)
    if result.error != "" { return result }
    i := 0
    for i < len(functions) {
        previous := 0
        for previous < i {
            if functions[previous].symbol == functions[i].symbol {
                result.error = "duplicate function: " + functions[i].symbol
                return result
            }
            previous = previous + 1
        }
        i = i + 1
    }
    entry := mir_program_function_index(functions, entry_symbol)
    if entry < 0 { result.error = "entry function not found: " + entry_symbol; return result }
    if functions[entry].external { result.error = "entry function has no body: " + entry_symbol; return result }
    calls := mir_program_call[]()
    i = 0
    for i < len(functions) {
        error := mir_program_function_error_with_globals(functions[i], functions, enums, records, globals)
        if error != "" { result.error = error; return result }
        b := 0
        for b < len(functions[i].blocks) {
            n := 0
            for n < len(functions[i].blocks[b].instructions) {
                ins := functions[i].blocks[b].instructions[n]
                if ins.op == "call" {
                    calls = mir_program_append_call(calls, functions[i].symbol, ins.symbol, functions[i].blocks[b].id, n)
                }
                n = n + 1
            }
            b = b + 1
        }
        i = i + 1
    }
    order := mir_program_global_order(globals, functions)
    if order.error != "" { result.error = order.error; return result }
    result.program = mir_program {
        package_name: package_name, entry_symbol: entry_symbol, functions: functions, calls: calls, enums: enums, records: records, globals: globals,
    }
    return result
}

func lower_mir_program(string package_name, string entry_symbol, mir_program_function[] functions) mir_program_result {
    return lower_mir_program_with_enums(package_name, entry_symbol, functions, mir_program_enum[]())
}

func mir_program_instruction_error(mir_program_function function_data, mir_program_function[] functions, mir_program_instruction instruction, int index) string {
    return mir_program_instruction_error_with_enums(function_data, functions, instruction, index, mir_program_enum[]())
}

func mir_program_function_error(mir_program_function function_data, mir_program_function[] functions) string {
    return mir_program_function_error_with_enums(function_data, functions, mir_program_enum[]())
}

func mir_program_record_index(mir_program_record[] records, string symbol) int {
    i := 0
    for i < len(records) {
        if records[i].symbol == symbol { return i }
        i = i + 1
    }
    return -1
}

func mir_program_record_field_index(mir_program_record record, string name) int {
    i := 0
    for i < len(record.field_names) {
        if record.field_names[i] == name { return i }
        i = i + 1
    }
    return -1
}

func mir_program_records_error(mir_program_record[] records, mir_program_enum[] enums) string {
    i := 0
    for i < len(records) {
        record := records[i]
        if record.symbol == "" || mir_program_record_index(records, record.symbol) != i || mir_program_enum_index(enums, record.symbol) >= 0 { return "invalid or duplicate record identity: " + record.symbol }
        if len(record.field_names) != len(record.field_types) { return "record field count: " + record.symbol }
        f := 0
        for f < len(record.field_names) {
            name := record.field_names[f]
            if name == "" || mir_program_record_field_index(record, name) != f { return "invalid or duplicate record field: " + record.symbol }
            field_type := record.field_types[f]
            if !mir_program_type_supported(field_type, records, enums) { return "unsupported record field type: " + field_type }
            f = f + 1
        }
        i = i + 1
    }
    return ""
}

func mir_program_record_instruction_error(mir_program_function function_data, mir_program_instruction ins, int index, mir_program_record[] records) string {
    record_index := mir_program_record_index(records, ins.symbol)
    if record_index < 0 { return "unknown record identity: " + ins.symbol }
    record := records[record_index]
    if ins.op == "record_new" {
        if ins.result_types[0] != record.symbol || ins.integer_value != 0 { return "record constructor result type" }
        if len(ins.field_names) != len(ins.operands) { return "record constructor field count" }
        i := 0
        for i < len(ins.operands) {
            field := mir_program_record_field_index(record, ins.field_names[i])
            if field < 0 { return "unknown record constructor field" }
            j := 0
            for j < i {
                if ins.field_names[j] == ins.field_names[i] { return "duplicate record constructor field" }
                j = j + 1
            }
            if mir_program_value_type(function_data, ins.operands[i], index) != record.field_types[field] { return "record constructor field type" }
            i = i + 1
        }
        return ""
    }
    field := ins.integer_value
    if len(ins.field_names) != 0 || field < 0 || field >= len(record.field_types) { return "record field index" }
    if ins.op == "record_set" {
        if len(ins.operands) != 2 || ins.result_types[0] != record.symbol { return "record store result type or arity" }
        if mir_program_value_type(function_data, ins.operands[1], index) != record.field_types[field] { return "record store field type" }
    } else if len(ins.operands) != 1 || ins.result_types[0] != record.field_types[field] { return "record projection result type or arity" }
    if mir_program_value_type(function_data, ins.operands[0], index) != record.symbol { return "record target type" }
    return ""
}

func lower_mir_program_with_enums(string package_name, string entry_symbol, mir_program_function[] functions, mir_program_enum[] enums) mir_program_result {
    return lower_mir_program_with_records(package_name, entry_symbol, functions, enums, mir_program_record[]())
}

func mir_program_instruction_error_with_enums(mir_program_function function_data, mir_program_function[] functions, mir_program_instruction ins, int index, mir_program_enum[] enums) string {
    return mir_program_instruction_error_with_records(function_data, functions, ins, index, enums, mir_program_record[]())
}

func mir_program_function_error_with_enums(mir_program_function function_data, mir_program_function[] functions, mir_program_enum[] enums) string {
    return mir_program_function_error_with_records(function_data, functions, enums, mir_program_record[]())
}

func mir_program_array_element(string type_name) string {
    if len(type_name) > 2 && __host_slice(type_name, 0, 2) == "[]" { return __host_slice(type_name, 2, len(type_name)) }
    if len(type_name) > 2 && __host_slice(type_name, len(type_name) - 2, len(type_name)) == "[]" { return __host_slice(type_name, 0, len(type_name) - 2) }
    return ""
}

func mir_program_record_index_unqualified(mir_program_record[] records, string type_name) int {
    i := 0
    for i < len(records) {
        symbol := records[i].symbol
        last_dot := -1
        j := 0
        for j < len(symbol) { if __host_slice(symbol, j, j + 1) == "." { last_dot = j } j = j + 1 }
        unqualified := symbol
        if last_dot >= 0 { unqualified = __host_slice(symbol, last_dot + 1, len(symbol)) }
        if unqualified == type_name { return i }
        i = i + 1
    }
    return -1
}

func mir_program_type_supported(string type_name, mir_program_record[] records, mir_program_enum[] enums) bool {
    referent := mir_program_reference_element(type_name)
    if referent != "" { return mir_program_type_supported(referent, records, enums) }
    if type_name == "string" || type_name == "int" || type_name == "()" || type_name == "bool" { return true }
    if mir_program_record_index(records, type_name) >= 0 { return true }
    if mir_program_record_index_unqualified(records, type_name) >= 0 { return true }
    if mir_program_enum_index(enums, type_name) >= 0 { return true }
    element := mir_program_array_element(type_name)
    if element != "" { return mir_program_type_supported(element, records, enums) }
    return false
}

// References nested in containers or tuples cannot escape through results.
func mir_program_contains_reference(string type_name) bool {
    i := 0
    for i < len(type_name) {
        if __host_slice(type_name, i, i + 1) == "&" { return true }
        i = i + 1
    }
    return false
}

func mir_program_reference_element(string type_name) string {
    if len(type_name) > 4 && __host_slice(type_name, 0, 4) == "&mut" { return __host_slice(type_name, 4, len(type_name)) }
    if len(type_name) > 1 && __host_slice(type_name, 0, 1) == "&" { return __host_slice(type_name, 1, len(type_name)) }
    return ""
}

func mir_program_reference_mutable(string type_name) bool {
    return len(type_name) > 4 && __host_slice(type_name, 0, 4) == "&mut"
}

func mir_program_reference_origin(mir_program_function function_data, int original) int {
    id := original
    remaining := 1
    b := 0
    for b < len(function_data.blocks) { remaining = remaining + len(function_data.blocks[b].instructions); b = b + 1 }
    for remaining > 0 {
        next := id
        b = 0
        for b < len(function_data.blocks) {
            i := 0
            for i < len(function_data.blocks[b].instructions) {
                ins := function_data.blocks[b].instructions[i]
                if ins.op == "reference_readonly" && len(ins.result_ids) == 1 && ins.result_ids[0] == id && len(ins.operands) == 1 { next = ins.operands[0] }
                i = i + 1
            }
            b = b + 1
        }
        if next == id { return id }
        id = next; remaining = remaining - 1
    }
    return -1
}

func mir_program_reference_instruction_error(mir_program_function function_data, mir_program_instruction ins, int index, mir_program_record[] records, mir_program_enum[] enums) string {
    if len(ins.result_ids) != 1 || len(ins.result_types) != 1 || len(ins.field_names) != 0 || ins.integer_value != 0 || ins.symbol == "" { return "invalid reference metadata" }
    if !mir_program_type_supported("&" + ins.symbol, records, enums) { return "unsupported reference referent" }
    if ins.op == "reference_new" {
        if len(ins.operands) != 1 || mir_program_reference_element(ins.result_types[0]) != ins.symbol { return "reference allocation result type or arity" }
        if mir_program_value_type(function_data, ins.operands[0], index) != ins.symbol { return "reference allocation value type" }
        return ""
    }
    if len(ins.operands) < 1 { return "missing reference operand" }
    reference_type := mir_program_value_type(function_data, ins.operands[0], index)
    if mir_program_reference_element(reference_type) != ins.symbol { return "reference operand referent type" }
    if ins.op == "reference_set" {
        if !mir_program_reference_mutable(reference_type) || len(ins.operands) != 2 || ins.result_types[0] != "()" { return "readonly reference store or invalid arity" }
        if mir_program_value_type(function_data, ins.operands[1], index) != ins.symbol { return "reference store value type" }
    } else if ins.op == "reference_readonly" {
        if len(ins.operands) != 1 || ins.result_types[0] != "&" + ins.symbol { return "invalid readonly reborrow" }
    } else if len(ins.operands) != 1 || ins.result_types[0] != ins.symbol { return "reference load result type or arity" }
    return ""
}

func mir_program_array_instruction_error(mir_program_function function_data, mir_program_instruction ins, int index, mir_program_record[] records, mir_program_enum[] enums) string {
    element := mir_program_array_element(ins.symbol)
    if element == "" || !mir_program_type_supported(element, records, enums) { return "unknown array element type" }
    if len(ins.field_names) != 0 || ins.integer_value != 0 { return "invalid array metadata" }
    if ins.op == "array_new" {
        if ins.result_types[0] != ins.symbol { return "array constructor result type" }
        i := 0
        for i < len(ins.operands) {
            if mir_program_value_type(function_data, ins.operands[i], index) != element { return "array constructor element type" }
            i = i + 1
        }
        return ""
    }
    if len(ins.operands) < 1 || mir_program_value_type(function_data, ins.operands[0], index) != ins.symbol { return "array target type" }
    if ins.op == "array_len" {
        if len(ins.operands) != 1 || ins.result_types[0] != "int" { return "array length type or arity" }
        return ""
    }
    if ins.op == "array_set" {
        if len(ins.operands) != 3 || ins.result_types[0] != ins.symbol { return "array store result type or arity" }
        if mir_program_value_type(function_data, ins.operands[1], index) != "int" || mir_program_value_type(function_data, ins.operands[2], index) != element { return "array store index or element type" }
        return ""
    }
    if len(ins.operands) != 2 { return "array operation arity" }
    if ins.op == "array_get" {
        if mir_program_value_type(function_data, ins.operands[1], index) != "int" || ins.result_types[0] != element { return "array index or result type" }
        return ""
    }
    if mir_program_value_type(function_data, ins.operands[1], index) != element || ins.result_types[0] != ins.symbol { return "array append element or result type" }
    return ""
}

func mir_program_scalar_instruction_error(mir_program_function function_data, mir_program_instruction ins, int index, mir_program_enum[] enums) string {
    if ins.op == "const_bool" {
        if ins.result_types[0] != "bool" || len(ins.operands) != 0 || (ins.integer_value != 0 && ins.integer_value != 1) { return "invalid bool constant" }
        return ""
    }
    if ins.op == "bool_to_int" {
        if ins.result_types[0] != "int" || len(ins.operands) != 1 { return "invalid bool conversion" }
        if mir_program_value_type(function_data, ins.operands[0], index) != "bool" { return "bool conversion source type" }
        return ""
    }
    if ins.result_types[0] != "bool" || len(ins.operands) != 2 { return "comparison result type or arity" }
    left := mir_program_value_type(function_data, ins.operands[0], index)
    right := mir_program_value_type(function_data, ins.operands[1], index)
    if left != right { return "comparison operand type mismatch" }
    if ins.op == "cmp_eq" || ins.op == "cmp_ne" {
        if left != "int" && left != "bool" && mir_program_enum_index(enums, left) < 0 { return "comparison requires scalar operands" }
    } else if left != "int" { return "ordered comparison requires int operands" }
    return ""
}

// String literal bytes are metadata, never an assembler identifier.
func mir_program_string_instruction_error(mir_program_function f, mir_program_instruction ins, int index) string {
    if len(ins.field_names) != 0 || ins.integer_value != 0 { return "invalid string metadata" }
    if ins.op == "const_string" {
        if len(ins.operands) != 0 || ins.result_types[0] != "string" { return "invalid string constant" }
        return ""
    }
    if ins.symbol != "" { return "unexpected string symbol" }
    if ins.op == "string_byte_at" || ins.op == "string_char_at" || ins.op == "string_slice" {
        count := 2
        result := "string"
        if ins.op == "string_slice" { count = 3 }
        if ins.op == "string_byte_at" { result = "int" }
        if len(ins.operands) != count || ins.result_types[0] != result { return "string access count or result type" }
        if mir_program_value_type(f, ins.operands[0], index) != "string" { return "string access target type" }
        i := 1
        for i < count {
            if mir_program_value_type(f, ins.operands[i], index) != "int" { return "string access index type" }
            i = i + 1
        }
        return ""
    }
    count := 2
    result := "string"
    if ins.op == "string_eq" || ins.op == "string_ne" || ins.op == "string_lt" || ins.op == "string_le" || ins.op == "string_gt" || ins.op == "string_ge" { result = "bool" }
    if ins.op == "string_len" { count = 1; result = "int" }
    if len(ins.operands) != count || ins.result_types[0] != result { return "string operand count or result type" }
    i := 0
    for i < count {
        if mir_program_value_type(f, ins.operands[i], index) != "string" { return "string operand type" }
        i = i + 1
    }
    return ""
}

// Exact signatures form the native runtime boundary; names never become assembler symbols.
func mir_native_intrinsic_result(string name) string {
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
func mir_native_intrinsic_parameters(string name) string[] {
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
func mir_native_intrinsic_error(mir_program_function f, mir_program_instruction ins, int index) string {
    result := mir_native_intrinsic_result(ins.symbol)
    if result == "?" { return "unknown native intrinsic: " + ins.symbol }
    params := mir_native_intrinsic_parameters(ins.symbol)
    if len(ins.field_names) != 0 || ins.integer_value != 0 { return "invalid native intrinsic metadata" }
    if len(ins.operands) != len(params) { return "native intrinsic argument count" }
    count := 1
    if result == "void" { count = 0 }
    if len(ins.result_types) != count { return "native intrinsic result count" }
    if count == 1 && ins.result_types[0] != result { return "native intrinsic result type" }
    i := 0
    for i < len(params) {
        if mir_program_value_type(f, ins.operands[i], index) != params[i] { return "native intrinsic argument type" }
        i = i + 1
    }
    return ""
}

// Legacy callers construct modules without globals.
func mir_program_instruction_error_with_records(mir_program_function f, mir_program_function[] functions, mir_program_instruction ins, int index, mir_program_enum[] enums, mir_program_record[] records) string {
    return mir_program_instruction_error_with_globals(f, functions, ins, index, enums, records, mir_program_global[]())
}
func mir_program_function_error_with_records(mir_program_function f, mir_program_function[] functions, mir_program_enum[] enums, mir_program_record[] records) string {
    return mir_program_function_error_with_globals(f, functions, enums, records, mir_program_global[]())
}
func lower_mir_program_with_records(string package_name, string entry_symbol, mir_program_function[] functions, mir_program_enum[] enums, mir_program_record[] records) mir_program_result {
    return lower_mir_program_with_globals(package_name, entry_symbol, functions, enums, records, mir_program_global[]())
}
func mir_program_global_index(mir_program_global[] globals, string symbol) int {
    i := 0
    for i < len(globals) {
        if globals[i].symbol == symbol { return i }
        i = i + 1
    }
    return -1
}
func mir_program_global_instruction_error(mir_program_function f, mir_program_instruction ins, int index, mir_program_global[] globals) string {
    if ins.op != "global_get" && ins.op != "global_set" { return "unknown global operation" }
    global_index := mir_program_global_index(globals, ins.symbol)
    if global_index < 0 { return "unknown global: " + ins.symbol }
    if len(ins.result_ids) != 1 || len(ins.field_names) != 0 || ins.integer_value != 0 { return "invalid global instruction metadata" }
    type_name := globals[global_index].type_name
    if ins.op == "global_get" {
        if len(ins.operands) != 0 || ins.result_types[0] != type_name { return "global load type or arity" }
    } else {
        if len(ins.operands) != 1 || ins.result_types[0] != "()" { return "global store result type or arity" }
        if mir_program_value_type(f, ins.operands[0], index) != type_name { return "global store operand type" }
    }
    return ""
}
func mir_program_globals_error(mir_program_global[] globals, mir_program_function[] functions, mir_program_record[] records, mir_program_enum[] enums) string {
    i := 0
    for i < len(globals) {
        global := globals[i]
        if global.symbol == "" || mir_program_global_index(globals, global.symbol) != i { return "invalid or duplicate global identity" }
        if !mir_program_type_supported(global.type_name, records, enums) { return "unsupported global type: " + global.type_name }
        if global.initializer != "" {
            target := mir_program_function_index(functions, global.initializer)
            if target < 0 { return "unknown global initializer: " + global.initializer }
            function := functions[target]
            if function.external || len(function.params) != 0 || len(function.result_types) != 1 { return "global initializer signature" }
            if function.result_types[0] != global.type_name { return "global initializer result type" }
        }
        i = i + 1
    }
    return ""
}
struct mir_program_global_order_result { int[] order; string error }
func mir_program_global_dependencies(mir_program_global[] globals, mir_program_function[] functions, int root) int[] {
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
                for i < len(function.blocks[b].instructions) {
                    ins := function.blocks[b].instructions[i]
                    if ins.op == "global_get" || ins.op == "global_set" {
                        target := mir_program_global_index(globals, ins.symbol)
                        if target >= 0 { dependencies[target] = 1 }
                    }
                    if ins.op == "call" {
                        target := mir_program_function_index(functions, ins.symbol)
                        if target >= 0 && visited[target] == 0 { pending.push(target) }
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
func mir_program_global_order(mir_program_global[] globals, mir_program_function[] functions) mir_program_global_order_result {
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
                    root := mir_program_function_index(functions, globals[g].initializer)
                    if root < 0 { return mir_program_global_order_result { order: order, error: "unknown global initializer" } }
                    dependencies := mir_program_global_dependencies(globals, functions, root)
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
        if !progress { return mir_program_global_order_result { order: order, error: "cyclic global initialization" } }
    }
    return mir_program_global_order_result { order: order, error: "" }
}
