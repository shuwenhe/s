package compile.internal.ir.lower

import (
    "compile.internal.ast"
    "compile.internal.mir"
    "std"
    "std.option"
    "std.prelude"
)

struct program_store_step {
    string kind
    int container
    int selector
    string type_name
    string value_type
}

struct program_lower_state {
    program_payload_layout[] payloads
    program_environment environment
    string store_root
    program_store_step[] store_steps
    mir_program_block[] blocks
    int block_id
    int created_block
    bool terminated
    mir_program_record[] records
    mir_program_enum[] enums
    mir_program_function signature
    mir_program_instruction[] instructions
    string[] binding_names
    int[] binding_values
    int next_value
    int expression_value
    string error
}

struct program_function_lower_result {
    mir_program_record[] records
    mir_program_function function_value
    string error
}

func program_item_package(source_file src, int index) string {
    if index < len(src.item_packages) && src.item_packages[index] != "" {
        return src.item_packages[index]
    }
    return src.pkg
}

// Repeated declarations of one external contract do not define another
// function. Compare canonical signature types; conflicting declarations and
// ordinary definitions still reach the independent duplicate-symbol gate.
func program_repeated_external_contract(source_file src, int index, function_decl current, mir_program_enum[] enums, mir_program_record[] records) bool {
    if current.body.is_some() { return false }
    pkg := program_item_package(src, index)
    signature := program_signature_with_records(pkg, current, enums, records)
    previous := 0
    for previous < index {
        switch src.items[previous] {
            item.function(declaration): {
                if declaration.body.is_none() && declaration.extern_library == current.extern_library
                    && declaration.sig.name == current.sig.name && program_item_package(src, previous) == pkg
                    && len(declaration.sig.generics) == len(current.sig.generics) {
                    candidate := program_signature_with_records(pkg, declaration, enums, records)
                    same := len(candidate.params) == len(signature.params) && len(candidate.result_types) == len(signature.result_types)
                    p := 0
                    for same && p < len(signature.params) { if candidate.params[p].type_name != signature.params[p].type_name { same = false }
                        p = p + 1 }
                    p = 0
                    for same && p < len(signature.result_types) { if candidate.result_types[p] != signature.result_types[p] { same = false }
                        p = p + 1 }
                    p = 0
                    for same && p < len(current.sig.generics) { if declaration.sig.generics[p] != current.sig.generics[p] { same = false }
                        p = p + 1 }
                    if same { return true }
                }
            }
            _: (),
        }
        previous = previous + 1
    }
    return false
}

func program_signature_with_enums(string package_name, function_decl declaration, mir_program_enum[] enums) mir_program_function {
    params := mir_program_parameter[]()
    i := 0
    for i < len(declaration.sig.params) {
        parameter := declaration.sig.params[i]
        params = append(params, mir_program_parameter {
            value_id: i, name: parameter.name, type_name: program_enum_type(parameter.type_name, package_name, enums),
        })
        i = i + 1
    }
    results := string[]()
    if declaration.sig.return_type.is_some() {
        result_type := declaration.sig.return_type.unwrap()
        if result_type != "" { results = append(results, program_enum_type(result_type, package_name, enums)) }
    }
    return mir_program_function {
        symbol: package_name + "." + declaration.sig.name, params: params,
        result_types: results, blocks: mir_program_block[](), external: declaration.body.is_none(),
    }
}

func program_binding_index(program_lower_state state, string name) int {
    i := len(state.binding_names)
    for i > 0 {
        i = i - 1
        if state.binding_names[i] == name { return i }
    }
    return -1
}

func program_expression_type(program_lower_state state, mir_program_function signature, int id) string {
    i := 0
    for i < len(signature.params) {
        if signature.params[i].value_id == id { return signature.params[i].type_name }
        i = i + 1
    }
    i = 0
    for i < len(state.instructions) {
        instruction := state.instructions[i]
        r := 0
        for r < len(instruction.result_ids) {
            if instruction.result_ids[r] == id { return instruction.result_types[r] }
            r = r + 1
        }
        i = i + 1
    }
    b := 0
    for b < len(state.blocks) {
        n := 0
        for n < len(state.blocks[b].instructions) {
            instruction := state.blocks[b].instructions[n]
            r := 0
            for r < len(instruction.result_ids) {
                if instruction.result_ids[r] == id { return instruction.result_types[r] }
                r = r + 1
            }
            n = n + 1
        }
        b = b + 1
    }
    return ""
}

func program_callee_path(expr callee) string {
    switch callee {
        expr.name(name): { return name.name }
        expr.member(member) : {
            root := program_callee_path(member.target.value)
            if root == "" { return "" }
            return root + "." + member.member
        }
        _ : { return "" },
    }
}

func program_is_qualified(string name) bool {
    i := 0
    for i < len(name) {
        if std.prelude.char_at(name, i) == "." { return true }
        i = i + 1
    }
    return false
}

func program_emit_integer(program_lower_state state, string literal) program_lower_state {
    value := 0
    i := 0
    if literal == "" { state.error = "empty integer literal"; return state }
    for i < len(literal) {
        ch := std.prelude.char_at(literal, i)
        digit := -1
        if ch == "0" { digit = 0 }
        if ch == "1" { digit = 1 }
        if ch == "2" { digit = 2 }
        if ch == "3" { digit = 3 }
        if ch == "4" { digit = 4 }
        if ch == "5" { digit = 5 }
        if ch == "6" { digit = 6 }
        if ch == "7" { digit = 7 }
        if ch == "8" { digit = 8 }
        if ch == "9" { digit = 9 }
        if digit < 0 { state.error = "unsupported integer spelling: " + literal; return state }
        if value > 922337203685477580 || (value == 922337203685477580 && digit > 7) {
            state.error = "integer literal exceeds int64: " + literal
            return state
        }
        value = value * 10 + digit
        i = i + 1
    }
    id := state.next_value
    state.next_value = id + 1
    state.instructions = append(state.instructions, mir_program_instruction {
        op: "const_int", result_ids: int[]{id}, result_types: string[]{"int"},
        operands: int[](), integer_value: value, symbol: "",
    })
    state.expression_value = id
    return state
}

func program_binary_opcode(string op) string {
    if op == "+" { return "add" }
    if op == "-" { return "sub" }
    if op == "*" { return "mul" }
    if op == "/" { return "div" }
    if op == "%" { return "mod" }
    if op == "==" { return "cmp_eq" }
    if op == "!=" { return "cmp_ne" }
    if op == "<" { return "cmp_lt" }
    if op == "<=" { return "cmp_le" }
    if op == ">" { return "cmp_gt" }
    if op == ">=" { return "cmp_ge" }
    return ""
}

func program_lower_expression(expr expression, string package_name, mir_program_function[] signatures, program_lower_state initial_state) program_lower_state {
    state := initial_state
    if state.error != "" { return state }
    switch expression {
        expr.tuple(tuple): {
            operands := int[]()
            names := string[]()
            type_name := "("
            i := 0
            for i < len(tuple.items) {
                state = program_lower_expression(tuple.items[i], package_name, signatures, state)
                if state.error != "" { return state }
                operands = append(operands, state.expression_value)
                names = append(names, "_" + std.prelude.to_string(i))
                if i > 0 { type_name = type_name + "," }
                type_name = type_name + program_expression_type(state, state.signature, state.expression_value)
                i = i + 1
            }
            type_name = type_name + ")"
            state.records = program_add_tuple_record(type_name, state.records)
            id := state.next_value
            state.next_value = id + 1
            state.instructions = append(state.instructions, mir_program_instruction { op: "record_new", result_ids: [id], result_types: [type_name], operands: operands, symbol: type_name, field_names: names })
            state.expression_value = id
            return state
        }
        expr.string(literal): {
            id := state.next_value
            state.next_value = id + 1
            state.instructions = append(state.instructions, mir_program_instruction { op: "const_string", result_ids: [id], result_types: ["string"], operands: int[](), symbol: literal.value })
            state.expression_value = id
            return state
        }
        expr.int(literal) : { return program_emit_integer(state, literal.value) }
        expr.bool(literal): {
            id := state.next_value
            state.next_value = id + 1
            value := 0
            if literal.value { value = 1 }
            state.instructions = append(state.instructions, mir_program_instruction { op: "const_bool", result_ids: [id], result_types: ["bool"], operands: int[](), integer_value: value })
            state.expression_value = id
            return state
        }
        expr.if(value): { return program_lower_if(value, package_name, signatures, state) }
        expr.switch(value): { return program_lower_switch(value, package_name, signatures, state) }
        expr.block(value): {
            names := state.binding_names
            count := len(names)
            state = program_lower_block(value, package_name, signatures, state)
            values := int[]()
            i := 0
            for i < count { values = append(values, state.binding_values[i]); i = i + 1 }
            state.binding_names = names
            state.binding_values = values
            return state
        }
        expr.while(value): { return program_lower_loop(option.some(value.condition.value), value.body, package_name, signatures, state) }
        expr.for(value): {
            if value.iterable.is_some() || len(value.names) != 0 { state.error = "for form requires explicit lowering"; return state }
            
            if value.init.is_some() || value.post.is_some() {
                return program_lower_three_part_for(value, package_name, signatures, state)
            }
            
            condition := option[expr].none
            if value.condition.is_some() { condition = option.some(value.condition.unwrap().value) }
            return program_lower_loop(condition, value.body, package_name, signatures, state)
        }
        expr.array(value): {
            array_type := ""
            if value.type_text.is_some() { array_type = program_record_type(value.type_text.unwrap(), package_name, state.records, state.enums) }
            operands := int[]()
            i := 0
            for i < len(value.items) {
                state = program_lower_expression(value.items[i], package_name, signatures, state)
                if state.error != "" { return state }
                operands = append(operands, state.expression_value)
                if array_type == "" { array_type = program_expression_type(state, state.signature, state.expression_value) + "[]" }
                i = i + 1
            }
            if mir_program_array_element(array_type) == "" { state.error = "empty array literal requires an explicit element type"; return state }
            return program_emit_array(state, "array_new", array_type, array_type, operands)
        }
        expr.index(value): {
            state = program_lower_expression(value.target.value, package_name, signatures, state)
            if state.error != "" { return state }
            target := state.expression_value
            array_type := program_expression_type(state, state.signature, target)
            element := mir_program_array_element(array_type)
            if element == "" { state.error = "index requires an array"; return state }
            state = program_lower_expression(value.index.value, package_name, signatures, state)
            if state.error != "" { return state }
            index := state.expression_value
            return program_emit_array(state, "array_get", array_type, element, [target, index])
        }
        expr.record(value): {
            symbol := program_record_type(value.type_name, package_name, state.records, state.enums)
            if mir_program_record_index(state.records, symbol) < 0 { state.error = "unknown record type: " + symbol; return state }
            operands := int[]()
            i := 0
            for i < len(value.field_values) {
                state = program_lower_expression(value.field_values[i], package_name, signatures, state)
                if state.error != "" { return state }
                operands = append(operands, state.expression_value)
                i = i + 1
            }
            id := state.next_value
            state.next_value = id + 1
            state.instructions = append(state.instructions, mir_program_instruction { op: "record_new", result_ids: [id], result_types: [symbol], operands: operands, symbol: symbol, integer_value: 0, field_names: value.field_names })
            state.expression_value = id
            return state
        }
        expr.member(member): {
            root := program_root_name(member.target.value)
            if root != "" && program_binding_index(state, root) < 0 {
                path := program_callee_path(expression)
                if program_payload_has_path(state.payloads, package_name, path) { return program_payload_constructor(path, expr[](), package_name, signatures, state) }
                return program_enum_constant(state, package_name, path)
            }
            state = program_lower_expression(member.target.value, package_name, signatures, state)
            if state.error != "" { return state }
            target := state.expression_value
            target_type := program_expression_type(state, state.signature, target)
            record_index := mir_program_record_index(state.records, target_type)
            if record_index < 0 { state.error = "member target is not a record: " + target_type; return state }
            record := state.records[record_index]
            field := mir_program_record_field_index(record, member.member)
            if field < 0 { state.error = "unknown record field: " + member.member; return state }
            id := state.next_value
            state.next_value = id + 1
            field_type := record.field_types[field]
            state.instructions = append(state.instructions, mir_program_instruction { op: "record_get", result_ids: [id], result_types: [field_type], operands: [target], symbol: target_type, integer_value: field })
            state.expression_value = id
            return state
        }
        expr.name(name) : {
            if name.name == "unit" {
                id := state.next_value
                state.next_value = id + 1
                state.instructions = append(state.instructions, mir_program_instruction { op: "const_unit", result_ids: [id], result_types: ["()"], operands: int[](), integer_value: 0, symbol: "" })
                state.expression_value = id
                return state
            }
            binding := program_binding_index(state, name.name)
            if binding < 0 { state.error = "undefined binding: " + name.name; return state }
            state.expression_value = state.binding_values[binding]
            return state
        }
        expr.binary(binary) : {
            if binary.op == "&&" || binary.op == "||" { return program_lower_short_circuit(binary, package_name, signatures, state) }
            op := program_binary_opcode(binary.op)
            if op == "" { state.error = "unsupported binary operation: " + binary.op; return state }
            state = program_lower_expression(binary.left.value, package_name, signatures, state)
            if state.error != "" { return state }
            left := state.expression_value
            state = program_lower_expression(binary.right.value, package_name, signatures, state)
            if state.error != "" { return state }
            right := state.expression_value
            id := state.next_value
            state.next_value = id + 1
            result_type := "int"
            if binary.op == "+" && program_expression_type(state, state.signature, left) == "string" {
                op = "string_concat"
                result_type = "string"
            }
            if program_expression_type(state, state.signature, left) == "string" {
                if op == "cmp_eq" { op = "string_eq" }
                if op == "cmp_ne" { op = "string_ne" }
                if op == "cmp_lt" { op = "string_lt" }
                if op == "cmp_le" { op = "string_le" }
                if op == "cmp_gt" { op = "string_gt" }
                if op == "cmp_ge" { op = "string_ge" }
                if op != "string_concat" { result_type = "bool" }
            }
            if op == "cmp_eq" || op == "cmp_ne" || op == "cmp_lt" || op == "cmp_le" || op == "cmp_gt" || op == "cmp_ge" { result_type = "bool" }
            state.instructions = append(state.instructions, mir_program_instruction {
                op: op, result_ids: int[]{id}, result_types: string[]{result_type},
                operands: int[]{left, right}, integer_value: 0, symbol: "",
            })
            state.expression_value = id
            return state
        }
        expr.call(call) : {
            if len(call.type_args) != 0 { state.error = "generic call requires monomorphization"; return state }
            path := program_callee_path(call.callee.value)
            if path == "" { state.error = "call requires a resolved direct callee"; return state }
            if program_payload_has_path(state.payloads, package_name, path) { return program_payload_constructor(path, call.args, package_name, signatures, state) }
            if path == "__host_byte_at" || path == "__host_char_at" || path == "__host_slice" {
                count := 2
                op := "string_byte_at"
                result := "int"
                if path == "__host_char_at" { op = "string_char_at"; result = "string" }
                if path == "__host_slice" { op = "string_slice"; result = "string"; count = 3 }
                if len(call.args) != count { state.error = "string intrinsic argument count"; return state }
                operands := int[]()
                i := 0
                for i < count {
                    state = program_lower_expression(call.args[i], package_name, signatures, state)
                    if state.error != "" { return state }
                    operands = append(operands, state.expression_value)
                    i = i + 1
                }
                id := state.next_value
                state.next_value = id + 1
                state.instructions = append(state.instructions, mir_program_instruction { op: op, result_ids: [id], result_types: [result], operands: operands })
                state.expression_value = id
                return state
            }
            if path == "len" || path == "append" {
                if len(call.args) < 1 || (path == "len" && len(call.args) != 1) || (path == "append" && len(call.args) < 2) { state.error = "array builtin argument count: " + path; return state }
                state = program_lower_expression(call.args[0], package_name, signatures, state)
                if state.error != "" { return state }
                target := state.expression_value
                array_type := program_expression_type(state, state.signature, target)
                if path == "len" && array_type == "string" {
                    id := state.next_value
                    state.next_value = id + 1
                    state.instructions = append(state.instructions, mir_program_instruction { op: "string_len", result_ids: [id], result_types: ["int"], operands: [target] })
                    state.expression_value = id
                    return state
                }
                if mir_program_array_element(array_type) == "" { state.error = "builtin requires an array: " + path; return state }
                if path == "len" { return program_emit_array(state, "array_len", array_type, "int", [target]) }
                i := 1
                for i < len(call.args) {
                    state = program_lower_expression(call.args[i], package_name, signatures, state)
                    if state.error != "" { return state }
                    element := state.expression_value
                    state = program_emit_array(state, "array_append", array_type, array_type, [target, element])
                    target = state.expression_value
                    i = i + 1
                }
                return state
            }
            if path == "int" {
                if len(call.args) != 1 { state.error = "int conversion expects one argument"; return state }
                state = program_lower_expression(call.args[0], package_name, signatures, state)
                if state.error != "" { return state }
                source_id := state.expression_value
                source_type := program_expression_type(state, state.signature, source_id)
                if source_type == "int" { return state }
                if source_type == "bool" {
                    id := state.next_value
                    state.next_value = id + 1
                    state.instructions = append(state.instructions, mir_program_instruction { op: "bool_to_int", result_ids: [id], result_types: ["int"], operands: [source_id] })
                    state.expression_value = id
                    return state
                }
                if mir_program_enum_index(state.enums, source_type) < 0 { state.error = "int conversion requires a scalar enum"; return state }
                id := state.next_value
                state.next_value = id + 1
                state.instructions = append(state.instructions, mir_program_instruction { op: "enum_to_int", result_ids: [id], result_types: ["int"], operands: [source_id], integer_value: 0, symbol: "" })
                state.expression_value = id
                return state
            }
            symbol := ""
            if call.resolved_callee.is_some() { symbol = call.resolved_callee.unwrap() }
            if program_is_qualified(path) {
                if mir_program_function_index(signatures, path) >= 0 {
                    symbol = path
                } else {
                    if !program_is_qualified(symbol) || mir_program_function_index(signatures, symbol) < 0 {
                        state.error = "qualified call requires package identity: " + path
                        return state
                    }
                }
            } else {
                if symbol == "" { symbol = path }
                if !program_is_qualified(symbol) { symbol = package_name + "." + symbol }
            }
            if (path == "eprintln" || path == "println" || path == "panic") && mir_program_function_index(signatures, package_name + "." + path) < 0 {
                symbol = "__native_builtin." + path
            }
            target := mir_program_function_index(signatures, symbol)
            if target < 0 { state.error = "unknown callee: " + symbol; return state }
            args := int[]()
            i := 0
            for i < len(call.args) {
                state = program_lower_expression(call.args[i], package_name, signatures, state)
                if state.error != "" { return state }
                args = append(args, state.expression_value)
                i = i + 1
            }
            result_types := signatures[target].result_types
            if len(result_types) > 1 { state.error = "multiple-result expression requires explicit binding"; return state }
            result_ids := int[]()
            state.expression_value = -1
            if len(result_types) == 1 {
                state.expression_value = state.next_value
                result_ids = append(result_ids, state.next_value)
                state.next_value = state.next_value + 1
            }
            state.instructions = append(state.instructions, mir_program_instruction {
                op: "call", result_ids: result_ids, result_types: result_types,
                operands: args, integer_value: 0, symbol: symbol,
            })
            return state
        }
        _ : { state.error = "unsupported P1: expression"; return state },
    }
}

func program_lower_function_with_records(string package_name, function_decl declaration, mir_program_function signature, mir_program_function[] signatures, mir_program_enum[] enums, mir_program_record[] records) program_function_lower_result {
    return program_lower_function_with_layouts(package_name, declaration, signature, signatures, enums, records, program_payload_layout[]())
}

func program_lower_function_with_layouts(string package_name, function_decl declaration, mir_program_function signature, mir_program_function[] signatures, mir_program_enum[] enums, mir_program_record[] records, program_payload_layout[] payloads) program_function_lower_result {
    output := program_function_lower_result { function_value: signature, records: records, error: "" }
    if len(declaration.sig.generics) != 0 { output.error = "generic function requires monomorphization: " + signature.symbol; return output }
    if declaration.body.is_none() {
        intrinsic_name := declaration.sig.name
        if declaration.intrinsic_name != "" { intrinsic_name = declaration.intrinsic_name }
        if declaration.extern_library == "intrinsic" && (mir_native_intrinsic_result(intrinsic_name) != "?" || intrinsic_name == "__runtime_len") {
            intrinsic := signature
            if intrinsic_name == "__runtime_len" { intrinsic = program_native_length_function(signature) }
            else { intrinsic = program_native_intrinsic_function(signature, intrinsic_name) }
            if intrinsic.external { output.error = "native intrinsic declaration signature: " + intrinsic_name; return output }
            output.function_value = intrinsic
        }
        return output
    }
    state := program_lower_state {
        payloads: payloads,
        instructions: mir_program_instruction[](), binding_names: string[](), binding_values: int[](), enums: enums, records: records, signature: signature,
        next_value: len(signature.params), expression_value: -1, error: "",
    }
    i := 0
    for i < len(signature.params) {
        state.binding_names = append(state.binding_names, signature.params[i].name)
        state.binding_values = append(state.binding_values, signature.params[i].value_id)
        i = i + 1
    }
    state.blocks = append(state.blocks, mir_program_block { id: 0, instructions: mir_program_instruction[](), terminator: "unreachable", return_values: int[](), successors: int[]() })
    state.block_id = 0
    state = program_lower_block(declaration.body.unwrap(), package_name, signatures, state)
    if state.error != "" { output.error = state.error; return output }
    if !state.terminated {
        returns := int[]()
        if len(signature.result_types) == 1 {
            if state.expression_value < 0 && signature.result_types[0] == "()" { state = program_emit_unit(state) }
            if state.expression_value < 0 { output.error = "missing return value: " + signature.symbol; return output }
            returns = append(returns, state.expression_value)
        }
        state = program_finish_block(state, "return", returns, int[]())
    }
    output.records = state.records
    output.function_value.blocks = state.blocks
    return output
}

func lower_source_program(source_file src) mir_program_result {
    empty := mir_program { package_name: src.pkg, entry_symbol: src.pkg + ".main", functions: mir_program_function[](), calls: mir_program_call[]() }
    result := mir_program_result { program: empty, error: "" }
    if len(src.item_packages) != 0 && len(src.item_packages) != len(src.items) {
        result.error = "source item package count mismatch"
        return result
    }
    enumeration_result := program_collect_enums(src)
    if enumeration_result.error != "" { result.error = enumeration_result.error; return result }
    enums := enumeration_result.enums
    payloads := program_collect_payloads(src)
    records := program_collect_records(src, enums)
    tuple_index := 0
    for tuple_index < len(src.items) {
        switch src.items[tuple_index] {
            item.function(declaration): {
                package_name := program_item_package(src, tuple_index)
                if declaration.sig.return_type.is_some() { records = program_add_tuple_record(program_record_type(declaration.sig.return_type.unwrap(), package_name, records, enums), records) }
                p := 0
                for p < len(declaration.sig.params) { records = program_add_tuple_record(program_record_type(declaration.sig.params[p].type_name, package_name, records, enums), records); p = p + 1 }
            }
            _: (),
        }
        tuple_index = tuple_index + 1
    }
    record_error := mir_program_records_error(records, enums)
    if record_error != "" { result.error = record_error; return result }
    r := 0
    for r < len(src.items) {
        switch src.items[r] {
            item.struct(declaration): { if len(declaration.generics) != 0 { result.error = "generic record requires monomorphization: " + declaration.name; return result } }
            _ : (),
        }
        r = r + 1
    }
    signatures := mir_program_function[]()
    i := 0
    for i < len(src.items) {
        switch src.items[i] {
            item.function(declaration) : {
                if !program_repeated_external_contract(src, i, declaration, enums, records) {
                    signatures = append(signatures, program_signature_with_records(program_item_package(src, i), declaration, enums, records))
                }
            }
            item.enum(_): (),
            item.struct(_): (),
            _ : { result.error = "requires explicit lowering for this declaration"; return result },
        }
        i = i + 1
    }
    builtin_names := ["eprintln", "println", "panic"];
    builtin_functions := mir_program_function[]()
    builtin_index := 0
    for builtin_index < len(builtin_names) {
        builtin_name := builtin_names[builtin_index]
        parameter := mir_program_parameter { value_id: 0, name: "text", type_name: "string" }
        signature := mir_program_function { symbol: "__native_builtin." + builtin_name, params: [parameter], result_types: string[](), external: true }
        signatures = append(signatures, signature)
        builtin_functions = append(builtin_functions, program_native_intrinsic_function(signature, builtin_name))
        builtin_index = builtin_index + 1
    }
    functions := mir_program_function[]()
    i = 0
    for i < len(src.items) {
        switch src.items[i] {
            item.function(declaration) : {
                if !program_repeated_external_contract(src, i, declaration, enums, records) {
                    lowered := program_lower_function_with_layouts(program_item_package(src, i), declaration, signatures[len(functions)], signatures, enums, records, payloads)
                    if lowered.error != "" { result.error = lowered.error; return result }
                    records = lowered.records
                    functions = append(functions, lowered.function_value)
                }
            }
            _ : (),
        }
        i = i + 1
    }
    builtin_index = 0
    for builtin_index < len(builtin_functions) {
        if program_has_call(functions, builtin_functions[builtin_index].symbol) {
            functions = append(functions, builtin_functions[builtin_index])
        }
        builtin_index = builtin_index + 1
    }
    return lower_mir_program_with_records(src.pkg, src.pkg + ".main", functions, enums, records)
}

func program_signature(string package_name, function_decl declaration) mir_program_function {
    return program_signature_with_enums(package_name, declaration, mir_program_enum[]())
}

func program_lower_function(string package_name, function_decl declaration, mir_program_function signature, mir_program_function[] signatures) program_function_lower_result {
    return program_lower_function_with_enums(package_name, declaration, signature, signatures, mir_program_enum[]())
}

func program_root_name(expr value) string {
    switch value {
        expr.name(name): { return name.name }
        expr.member(member): { return program_root_name(member.target.value) }
        _ : { return "" },
    }
}

func program_record_type(string type_name, string package_name, mir_program_record[] records, mir_program_enum[] enums) string {
    tuple := program_tuple_types(type_name)
    if len(tuple) > 1 {
        result := "("
        i := 0
        for i < len(tuple) { if i > 0 { result = result + "," }
            result = result + program_record_type(tuple[i], package_name, records, enums); i = i + 1 }
        return result + ")"
    }
    element := mir_program_array_element(type_name)
    if element != "" { return program_record_type(element, package_name, records, enums) + "[]" }
    if mir_program_record_index(records, package_name + "." + type_name) >= 0 { return package_name + "." + type_name }
    return program_enum_type(type_name, package_name, enums)
}

func program_collect_records(source_file source, mir_program_enum[] enums) mir_program_record[] {
    records := mir_program_record[]()
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.struct(declaration): {
                names := string[]()
                types := string[]()
                f := 0
                for f < len(declaration.fields) {
                    names = append(names, declaration.fields[f].name)
                    types = append(types, declaration.fields[f].type_name)
                    f = f + 1
                }
                records = append(records, mir_program_record { symbol: program_item_package(source, i) + "." + declaration.name, field_names: names, field_types: types })
            }
            _ : (),
        }
        i = i + 1
    }
    payloads := program_collect_payloads(source)
    i = 0
    for i < len(payloads) {
        names := ["__variant"];
        types := ["int"];
        v := 0
        for v < len(payloads[i].variants) {
            if payloads[i].payload_types[v] != "" {
                names.push("__payload_" + payloads[i].variants[v])
                types.push(payloads[i].payload_types[v])
            }
            v = v + 1
        }
        records.push(mir_program_record { symbol: payloads[i].symbol, field_names: names, field_types: types })
        i = i + 1
    }
    i = 0
    for i < len(records) {
        package_name := ""
        j := 0
        for j < len(source.items) {
            switch source.items[j] {
                item.struct(declaration): { if program_item_package(source, j) + "." + declaration.name == records[i].symbol { package_name = program_item_package(source, j) } }
                item.enum(declaration): { if program_item_package(source, j) + "." + declaration.name == records[i].symbol { package_name = program_item_package(source, j) } }
                _ : (),
            }
            j = j + 1
        }
        f := 0
        for f < len(records[i].field_types) {
            records[i].field_types[f] = program_record_type(records[i].field_types[f], package_name, records, enums)
            f = f + 1
        }
        i = i + 1
    }
    return records
}

func program_signature_with_records(string package_name, function_decl declaration, mir_program_enum[] enums, mir_program_record[] records) mir_program_function {
    signature := program_signature_with_enums(package_name, declaration, enums)
    i := 0
    for i < len(signature.params) {
        signature.params[i].type_name = program_record_type(signature.params[i].type_name, package_name, records, enums)
        i = i + 1
    }
    i = 0
    for i < len(signature.result_types) {
        signature.result_types[i] = program_record_type(signature.result_types[i], package_name, records, enums)
        i = i + 1
    }
    return signature
}

func program_lower_function_with_enums(string package_name, function_decl declaration, mir_program_function signature, mir_program_function[] signatures, mir_program_enum[] enums) program_function_lower_result {
    return program_lower_function_with_records(package_name, declaration, signature, signatures, enums, mir_program_record[]())
}

func program_emit_array(program_lower_state initial, string op, string array_type, string result_type, int[] operands) program_lower_state {
    state := initial
    id := state.next_value
    state.next_value = id + 1
    state.instructions = append(state.instructions, mir_program_instruction { op: op, result_ids: [id], result_types: [result_type], operands: operands, symbol: array_type, integer_value: 0 })
    state.expression_value = id
    return state
}

func program_copy_values(int[] values) int[] {
    output := int[]()
    i := 0
    for i < len(values) { output = append(output, values[i]); i = i + 1 }
    return output
}

func program_new_block(program_lower_state initial) program_lower_state {
    state := initial
    id := len(state.blocks)
    state.blocks = append(state.blocks, mir_program_block { id: id, instructions: mir_program_instruction[](), terminator: "unreachable", return_values: int[](), successors: int[]() })
    state.created_block = id
    return state
}

func program_open_block(program_lower_state initial, int id) program_lower_state {
    state := initial
    state.block_id = id
    state.instructions = mir_program_instruction[]()
    state.terminated = false
    state.expression_value = -1
    return state
}

func program_finish_block(program_lower_state initial, string terminator, int[] values, int[] successors) program_lower_state {
    state := initial
    state.blocks[state.block_id] = mir_program_block { id: state.block_id, instructions: state.instructions, terminator: terminator, return_values: values, successors: successors }
    state.terminated = true
    return state
}

func program_emit_unit(program_lower_state state) program_lower_state {
    return program_lower_expression(expr.name(name_expr { name: "unit", inferred_type: option.none }), "", mir_program_function[](), state)
}

func program_emit_phi(program_lower_state initial, int first, int second, int first_block, int second_block) program_lower_state {
    state := initial
    if first == second { state.expression_value = first; return state }
    type_name := program_expression_type(state, state.signature, first)
    if type_name == "" || type_name != program_expression_type(state, state.signature, second) { state.error = "phi input type mismatch"; return state }
    operands := int[]{first, second}
    if first_block > second_block { operands = [second, first] }
    id := state.next_value
    state.next_value = id + 1
    state.instructions = append(state.instructions, mir_program_instruction { op: "phi", result_ids: [id], result_types: [type_name], operands: operands })
    state.expression_value = id
    return state
}

func program_lower_block(block_expr body, string package_name, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := initial
    i := 0
    for i < len(body.statements) {
        if state.terminated { state.error = "statement after terminating control flow"; return state }
        switch body.statements[i] {
            stmt.multi(binding): {
                state = program_lower_expression(binding.value, package_name, signatures, state)
                if state.error != "" { return state }
                tuple_value := state.expression_value
                type_name := program_expression_type(state, state.signature, tuple_value)
                types := program_tuple_types(type_name)
                if len(types) != len(binding.targets) { state.error = "parallel assignment arity mismatch"; return state }
                j := 0
                for j < len(binding.targets) {
                    name := ""
                    switch binding.targets[j] { expr.name(identifier): name = identifier.name, _: (), }
                    if name == "" { state.error = "parallel assignment requires local names"; return state }
                    if name != "_" {
                        id := state.next_value
                        state.next_value = id + 1
                        field_type := types[j]
                        state.instructions = append(state.instructions, mir_program_instruction { op: "record_get", result_ids: [id], result_types: [field_type], operands: [tuple_value], symbol: type_name, integer_value: j })
                        index := program_binding_index(state, name)
                        if binding.declaration {
                            if index >= 0 { state.error = "duplicate parallel binding"; return state }
                            state.binding_names = append(state.binding_names, name)
                            state.binding_values = append(state.binding_values, id)
                        } else {
                            if index < 0 { state.error = "parallel assignment to undefined binding"; return state }
                            if program_expression_type(state, state.signature, state.binding_values[index]) != field_type { state.error = "parallel assignment type mismatch"; return state }
                            state.binding_values[index] = id
                        }
                    }
                    j = j + 1
                }
            }
            stmt.let(binding): {
                if program_binding_index(state, binding.name) >= 0 { state.error = "duplicate binding: " + binding.name; return state }
                state = program_lower_expression(binding.value, package_name, signatures, state)
                if state.error != "" { return state }
                if state.expression_value < 0 { state.error = "cannot bind a void expression"; return state }
                if binding.type_name.is_some() && program_record_type(binding.type_name.unwrap(), package_name, state.records, state.enums) != program_expression_type(state, state.signature, state.expression_value) { state.error = "local type mismatch: " + binding.name; return state }
                state.binding_names = append(state.binding_names, binding.name)
                state.binding_values = append(state.binding_values, state.expression_value)
            }
            stmt.assign(binding): {
                index := program_binding_index(state, binding.name)
                if index < 0 { state.error = "assignment to undefined binding"; return state }
                previous_type := program_expression_type(state, state.signature, state.binding_values[index])
                state = program_lower_expression(binding.value, package_name, signatures, state)
                if state.error != "" { return state }
                if previous_type != program_expression_type(state, state.signature, state.expression_value) { state.error = "assignment type mismatch"; return state }
                state.binding_values[index] = state.expression_value
            }
            stmt.store(value): { state = program_lower_store(value, package_name, signatures, state) }
            stmt.expr(value): { state = program_lower_expression(value.expr, package_name, signatures, state) }
            stmt.return(value): {
                returns := int[]()
                if value.value.is_some() {
                    state = program_lower_expression(value.value.unwrap(), package_name, signatures, state)
                    if state.error != "" { return state }
                    if state.expression_value < 0 { state.error = "return expression has no value"; return state }
                    returns = append(returns, state.expression_value)
                } else if len(state.signature.result_types) == 1 && state.signature.result_types[0] == "()" {
                    state = program_emit_unit(state)
                    returns = append(returns, state.expression_value)
                }
                state = program_finish_block(state, "return", returns, int[]())
            }
            _ : { state.error = "statement requires explicit CFG lowering"; return state },
        }
        if state.error != "" { return state }
        i = i + 1
    }
    if body.final_expr.is_some() {
        if state.terminated { state.error = "expression after terminating control flow"; return state }
        state = program_lower_expression(body.final_expr.unwrap(), package_name, signatures, state)
    } else { state.expression_value = -1 }
    return state
}

func program_lower_if(if_expr branch, string package_name, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := program_lower_expression(branch.condition.value, package_name, signatures, initial)
    if state.error != "" { return state }
    condition := state.expression_value
    names := state.binding_names
    base := program_copy_values(state.binding_values)
    state = program_new_block(state)
    then_block := state.created_block
    state = program_new_block(state)
    else_block := state.created_block
    state = program_new_block(state)
    merge_block := state.created_block
    state = program_finish_block(state, "branch", [condition], [then_block, else_block])
    state = program_open_block(state, then_block)
    state.binding_values = program_copy_values(base)
    state = program_lower_block(branch.then_branch, package_name, signatures, state)
    if state.error != "" { return state }
    then_live := !state.terminated
    if then_live && state.expression_value < 0 { state = program_emit_unit(state) }
    then_result := state.expression_value
    then_values := program_copy_values(state.binding_values)
    then_end := state.block_id
    if then_live { state = program_finish_block(state, "jump", int[](), [merge_block]) }
    state = program_open_block(state, else_block)
    state.binding_names = names
    state.binding_values = program_copy_values(base)
    if branch.else_branch.is_some() { state = program_lower_expression(branch.else_branch.unwrap().value, package_name, signatures, state) }
    if state.error != "" { return state }
    else_live := !state.terminated
    if else_live && state.expression_value < 0 { state = program_emit_unit(state) }
    else_result := state.expression_value
    else_values := program_copy_values(state.binding_values)
    else_end := state.block_id
    if else_live { state = program_finish_block(state, "jump", int[](), [merge_block]) }
    state = program_open_block(state, merge_block)
    state.binding_names = names
    state.binding_values = program_copy_values(base)
    if !then_live && !else_live { state.terminated = true; return state }
    i := 0
    for i < len(base) {
        if then_live && else_live { state = program_emit_phi(state, then_values[i], else_values[i], then_end, else_end) }
        else if then_live { state.expression_value = then_values[i] }
        else { state.expression_value = else_values[i] }
        if state.error != "" { return state }
        state.binding_values[i] = state.expression_value
        i = i + 1
    }
    if then_live && else_live { state = program_emit_phi(state, then_result, else_result, then_end, else_end) }
    else if then_live { state.expression_value = then_result }
    else { state.expression_value = else_result }
    return state
}

func program_lower_loop(option[expr] condition, block_expr body, string package_name, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    return program_lower_loop_with_post(condition, body, option[box[stmt]].none, package_name, signatures, initial)
}

func program_lower_loop_with_post(option[expr] condition, block_expr body, option[box[stmt]] post, string package_name, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := initial
    names := state.binding_names
    base := program_copy_values(state.binding_values)
    state = program_new_block(state)
    header := state.created_block
    state = program_new_block(state)
    body_block := state.created_block
    state = program_new_block(state)
    exit := state.created_block
    state = program_finish_block(state, "jump", int[](), [header])
    state = program_open_block(state, header)
    phi_values := int[]()
    i := 0
    for i < len(base) {
        type_name := program_expression_type(state, state.signature, base[i])
        id := state.next_value
        state.next_value = id + 1
        incoming := base[i]
        state.instructions = append(state.instructions, mir_program_instruction { op: "phi", result_ids: [id], result_types: [type_name], operands: [incoming] })
        phi_values = append(phi_values, id)
        i = i + 1
    }
    state.binding_values = program_copy_values(phi_values)
    if condition.is_some() { state = program_lower_expression(condition.unwrap(), package_name, signatures, state) }
    else { state = program_lower_expression(expr.bool(bool_expr { value: true, inferred_type: option.none }), package_name, signatures, state) }
    if state.error != "" { return state }
    condition_value := state.expression_value
    condition_bindings := program_copy_values(state.binding_values)
    state = program_finish_block(state, "branch", [condition_value], [body_block, exit])
    state = program_open_block(state, body_block)
    state.binding_values = program_copy_values(condition_bindings)
    state = program_lower_block(body, package_name, signatures, state)
    if state.error != "" { return state }
    if !state.terminated && post.is_some() {
        state.binding_names = names
        loop_values := int[]()
        p := 0
        for p < len(base) { loop_values.push(state.binding_values[p]); p = p + 1 }
        state.binding_values = loop_values
        state = program_lower_stmt(post.unwrap().value, package_name, signatures, state)
        if state.error != "" { return state }
    }
    if !state.terminated {
        back_values := program_copy_values(state.binding_values)
        state = program_finish_block(state, "jump", int[](), [header])
        i = 0
        for i < len(base) {
            incoming := base[i]
            back := back_values[i]
            state.blocks[header] = program_set_phi_operands(state.blocks[header], i, [incoming, back])
            i = i + 1
        }
    }
    state = program_open_block(state, exit)
    state.binding_names = names
    state.binding_values = program_copy_values(condition_bindings)
    return program_emit_unit(state)
}

func program_lower_short_circuit(compile.internal.ast.binary_expr binary, string package_name, mir_program_function[] signatures, program_lower_state state) program_lower_state {
    then_value := binary.right.value
    otherwise := expr.bool(bool_expr { value: false, inferred_type: option.none })
    if binary.op == "||" { then_value = expr.bool(bool_expr { value: true, inferred_type: option.none }); otherwise = binary.right.value }
    branch := if_expr { condition: binary.left, then_branch: block_expr { statements: stmt[](), final_expr: option.some(then_value), inferred_type: option.none }, else_branch: option.some(std.prelude.box(otherwise)), inferred_type: option.none }
    return program_lower_if(branch, package_name, signatures, state)
}

func program_set_phi_operands(mir_program_block initial, int index, int[] operands) mir_program_block {
    block := initial
    instruction := block.instructions[index]
    instruction.operands = operands
    block.instructions[index] = instruction
    return block
}

func program_prepare_store(expr target, string package_name, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := initial
    switch target {
        expr.name(name): {
            index := program_binding_index(state, name.name)
            if index < 0 { state.error = "store to undefined binding"; return state }
            state.store_root = name.name
            state.expression_value = state.binding_values[index]
            return state
        }
        expr.member(member): {
            state = program_prepare_store(member.target.value, package_name, signatures, state)
            if state.error != "" { return state }
            container := state.expression_value
            type_name := program_expression_type(state, state.signature, container)
            record_index := mir_program_record_index(state.records, type_name)
            if record_index < 0 { state.error = "store member target is not a record"; return state }
            record := state.records[record_index]
            field := mir_program_record_field_index(record, member.member)
            if field < 0 { state.error = "store to unknown record field"; return state }
            field_type := record.field_types[field]
            id := state.next_value
            state.next_value = id + 1
            state.instructions = append(state.instructions, mir_program_instruction { op: "record_get", result_ids: [id], result_types: [field_type], operands: [container], symbol: type_name, integer_value: field })
            state.store_steps = append(state.store_steps, program_store_step { kind: "record", container: container, selector: field, type_name: type_name, value_type: field_type })
            state.expression_value = id
            return state
        }
        expr.index(index): {
            state = program_prepare_store(index.target.value, package_name, signatures, state)
            if state.error != "" { return state }
            container := state.expression_value
            type_name := program_expression_type(state, state.signature, container)
            element := mir_program_array_element(type_name)
            if element == "" { state.error = "store index target is not an array"; return state }
            outer_root := state.store_root
            outer_steps := state.store_steps
            state = program_lower_expression(index.index.value, package_name, signatures, state)
            if state.error != "" { return state }
            state.store_root = outer_root
            state.store_steps = outer_steps
            selector := state.expression_value
            state = program_emit_array(state, "array_get", type_name, element, [container, selector])
            state.store_steps = append(state.store_steps, program_store_step { kind: "array", container: container, selector: selector, type_name: type_name, value_type: element })
            return state
        }
        _ : { state.error = "store requires a named place"; return state },
    }
}

func program_lower_store(store_stmt store, string package_name, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := initial
    state.store_root = ""
    state.store_steps = program_store_step[]()
    state = program_prepare_store(store.target, package_name, signatures, state)
    if state.error != "" { return state }
    root := state.store_root
    steps := state.store_steps
    previous := state.expression_value
    previous_type := program_expression_type(state, state.signature, previous)
    state = program_lower_expression(store.value, package_name, signatures, state)
    if state.error != "" { return state }
    rhs := state.expression_value
    if store.op != "=" {
        op := program_binary_opcode(std.prelude.prelude_slice(store.op, 0, len(store.op) - 1))
        if op == "" { state.error = "unsupported compound store operation"; return state }
        id := state.next_value
        state.next_value = id + 1
        state.instructions = append(state.instructions, mir_program_instruction { op: op, result_ids: [id], result_types: [previous_type], operands: [previous, rhs] })
        rhs = id
    }
    if previous_type != program_expression_type(state, state.signature, rhs) { state.error = "store type mismatch"; return state }
    i := len(steps)
    for i > 0 {
        i = i - 1
        step := steps[i]
        if step.kind == "record" {
            id := state.next_value
            state.next_value = id + 1
            container := step.container
            type_name := step.type_name
            state.instructions = append(state.instructions, mir_program_instruction { op: "record_set", result_ids: [id], result_types: [type_name], operands: [container, rhs], symbol: type_name, integer_value: step.selector })
            rhs = id
        } else {
            container := step.container
            selector := step.selector
            state = program_emit_array(state, "array_set", step.type_name, step.type_name, [container, selector, rhs])
            rhs = state.expression_value
        }
    }
    index := program_binding_index(state, root)
    state.binding_values[index] = rhs
    state.expression_value = rhs
    return state
}

// Tuple values use the same typed aggregate representation and native return
// convention as records; field order is part of the structural tuple identity.
func program_tuple_types(string text) string[] {
    types := string[]()
    if len(text) < 5 || std.prelude.char_at(text, 0) != "(" || std.prelude.char_at(text, len(text) - 1) != ")" { return types }
    start := 1
    depth := 0
    i := 1
    for i < len(text) - 1 {
        ch := std.prelude.char_at(text, i)
        if ch == "[" || ch == "(" { depth = depth + 1 }
        else if ch == "]" || ch == ")" { depth = depth - 1 }
        else if ch == "," && depth == 0 { types = append(types, std.prelude.prelude_slice(text, start, i)); start = i + 1 }
        i = i + 1
    }
    if len(types) > 0 { types = append(types, std.prelude.prelude_slice(text, start, len(text) - 1)) }
    return types
}

func program_add_tuple_record(string type_name, mir_program_record[] initial) mir_program_record[] {
    records := initial
    types := program_tuple_types(type_name)
    if len(types) < 2 || mir_program_record_index(records, type_name) >= 0 { return records }
    names := string[]()
    i := 0
    for i < len(types) {
        records = program_add_tuple_record(types[i], records)
        names = append(names, "_" + std.prelude.to_string(i))
        i = i + 1
    }
    return append(records, mir_program_record { symbol: type_name, field_names: names, field_types: types })
}

func program_lower_three_part_for(compile.internal.ast.for_expr for_value, string package_name, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := initial
    names := state.binding_names
    count := len(names)
    if for_value.init.is_some() {
        state = program_lower_stmt(for_value.init.unwrap().value, package_name, signatures, state)
        if state.error != "" { return state }
    }
    condition := option[expr].none
    if for_value.condition.is_some() { condition = option.some(for_value.condition.unwrap().value) }
    state = program_lower_loop_with_post(condition, for_value.body, for_value.post, package_name, signatures, state)
    if state.error != "" { return state }
    values := int[]()
    i := 0
    for i < count { values.push(state.binding_values[i]); i = i + 1 }
    state.binding_names = names
    state.binding_values = values
    return state
}

func program_lower_stmt(stmt statement, string package_name, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := initial
    switch statement {
        stmt.let(binding): {
            if program_binding_index(state, binding.name) >= 0 { state.error = "duplicate binding: " + binding.name; return state }
            state = program_lower_expression(binding.value, package_name, signatures, state)
            if state.error != "" { return state }
            if state.expression_value < 0 { state.error = "cannot bind a void expression"; return state }
            state.binding_names = append(state.binding_names, binding.name)
            state.binding_values = append(state.binding_values, state.expression_value)
        }
        stmt.assign(binding): {
            index := program_binding_index(state, binding.name)
            if index < 0 { state.error = "assignment to undefined binding"; return state }
            state = program_lower_expression(binding.value, package_name, signatures, state)
            if state.error != "" { return state }
            state.binding_values[index] = state.expression_value
        }
        stmt.expr(value): {
            state = program_lower_expression(value.expr, package_name, signatures, state)
        }
        _: {
            state.error = "unsupported statement in for init"
        }
    }
    return state
}

// A recognized extern becomes an ordinary function whose only effect is a
// signature-checked runtime operation. Unknown externs remain external.
func program_native_intrinsic_function(mir_program_function initial_signature, string name) mir_program_function {
    signature := initial_signature
    result := mir_native_intrinsic_result(name)
    params := mir_native_intrinsic_parameters(name)
    if result == "?" || len(params) != len(signature.params) { return signature }
    count := 1
    if result == "void" { count = 0 }
    if len(signature.result_types) != count { return signature }
    if count == 1 && signature.result_types[0] != result { return signature }
    operands := int[]()
    i := 0
    for i < len(params) {
        if signature.params[i].type_name != params[i] { return signature }
        operands = append(operands, signature.params[i].value_id)
        i = i + 1
    }
    ids := int[]()
    if count == 1 { result_id := len(params); ids = [result_id] }
    instruction := mir_program_instruction { op: "native_intrinsic", operands: operands, result_ids: ids, result_types: signature.result_types, symbol: name }
    block := mir_program_block { id: 0, instructions: [instruction], terminator: "return", return_values: ids }
    blocks := mir_program_block[]()
    blocks = append(blocks, block)
    signature.blocks = blocks
    signature.external = false
    return signature
}

func program_has_call(mir_program_function[] functions, string symbol) bool {
    f := 0
    for f < len(functions) {
        b := 0
        for b < len(functions[f].blocks) {
            i := 0
            for i < len(functions[f].blocks[b].instructions) {
                instruction := functions[f].blocks[b].instructions[i]
                if instruction.op == "call" && instruction.symbol == symbol { return true }
                i = i + 1
            }
            b = b + 1
        }
        f = f + 1
    }
    return false
}

// Generic length intrinsics must be specialized to one concrete supported
// container type before crossing into typed MIR. There is no wildcard runtime ABI.
func program_native_length_function(mir_program_function initial_signature) mir_program_function {
    signature := initial_signature
    if len(signature.params) != 1 || len(signature.result_types) != 1 || signature.result_types[0] != "int" { return signature }
    parameter := signature.params[0]
    op := "array_len"
    symbol := parameter.type_name
    if parameter.type_name == "string" { op = "string_len"; symbol = "" }
    else if mir_program_array_element(parameter.type_name) == "" { return signature }
    result_id := parameter.value_id + 1
    parameter_id := parameter.value_id
    instruction := mir_program_instruction { op: op, result_ids: [result_id], result_types: ["int"], operands: [parameter_id], symbol: symbol }
    block := mir_program_block { id: 0, instructions: [instruction], terminator: "return", return_values: [result_id] }
    blocks := mir_program_block[]()
    blocks = append(blocks, block)
    signature.blocks = blocks
    signature.external = false
    return signature
}
