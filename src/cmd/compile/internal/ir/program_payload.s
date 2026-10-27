package compile.internal.ir.lower
import ("compile.internal.ast"; "compile.internal.mir"; "std.option"; "std.prelude")

// Helper to create binary expressions, avoiding Seed inline enum variant issues
func make_binary_expr(expr left, string op, expr right) expr {
    expr.binary(binary_expr { left: std.prelude.box(left), op: op, right: std.prelude.box(right), inferred_type: option.none })
}

// Payload enums keep their nominal type and lower to immutable typed records.
// Each variant has a declared payload field; only the selected field is set.
struct program_payload_layout {
    string symbol
    string package_name
    string[] variants
    int[] tags
    string[] payload_types
}
struct program_pattern_result {
    expr condition
    string[] names
    expr[] values
    string error
}
struct program_switch_exit { int block; int result; int[] bindings }

func program_collect_payloads(source_file source) program_payload_layout[] {
    output := program_payload_layout[]()
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.enum(declaration): {
                payload := false
                v := 0
                for v < len(declaration.variants) { if declaration.variants[v].payload.is_some() { payload = true }
 v = v + 1 }
                if payload && len(declaration.generics) == 0 {
                    pkg := program_item_package(source, i)
                    layout := program_payload_layout { symbol: pkg + "." + declaration.name, package_name: pkg }
                    tag := 0
                    v = 0
                    for v < len(declaration.variants) {
                        variant := declaration.variants[v]
                        if variant.has_explicit_value { tag = variant.explicit_value }
                        layout.variants.push(variant.name)
                        layout.tags.push(tag)
                        type_name := ""
                        if variant.payload.is_some() { type_name = variant.payload.unwrap() }
                        layout.payload_types.push(type_name)
                        tag = tag + 1
                        v = v + 1
                    }
                    output.push(layout)
                }
            }
            _: (),
        }
        i = i + 1
    }
    return output
}

func program_payload_index(program_payload_layout[] layouts, string symbol) int {
    i := 0
    for i < len(layouts) { if layouts[i].symbol == symbol { return i }
 i = i + 1 }
    return -1
}
func program_payload_has_path(program_payload_layout[] layouts, string pkg, string path) bool {
    i := 0
    for i < len(layouts) {
        v := 0
        for v < len(layouts[i].variants) {
            full := layouts[i].symbol + "." + layouts[i].variants[v]
            if path == full || pkg + "." + path == full { return true }
            v = v + 1
        }
        i = i + 1
    }
    return false
}
func program_payload_constructor(string path, expr[] arguments, string pkg, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := initial
    i := 0
    for i < len(state.payloads) {
        layout := state.payloads[i]
        v := 0
        for v < len(layout.variants) {
            full := layout.symbol + "." + layout.variants[v]
            if path == full || pkg + "." + path == full {
                count := 0
                if layout.payload_types[v] != "" { count = 1 }
                if len(arguments) != count { state.error = "enum constructor payload arity: " + full; return state }
                state = program_emit_integer(state, std.prelude.to_string(layout.tags[v]))
                tag_value := state.expression_value
                operands := [tag_value];
                names := ["__variant"];
                if count == 1 {
                    state = program_lower_expression(arguments[0], pkg, signatures, state)
                    if state.error != "" { return state }
                    operands.push(state.expression_value)
                    names.push("__payload_" + layout.variants[v])
                }
                id := state.next_value
                state.next_value = id + 1
                symbol := layout.symbol
                state.instructions.push(mir_program_instruction { op: "record_new", result_ids: [id], result_types: [symbol], operands: operands, field_names: names, symbol: layout.symbol })
                state.expression_value = id
                return state
            }
            v = v + 1
        }
        i = i + 1
    }
    state.error = "unknown payload constructor: " + path
    return state
}

func program_pattern_condition(pattern pattern_value, expr subject, string type_name, string pkg, program_lower_state state) program_pattern_result {
    always := expr.bool(bool_expr { value: true, inferred_type: option.none })
    output := program_pattern_result { condition: always }
    switch pattern_value {
        pattern.wildcard(_): { return output }
        pattern.name(name): {
            if name.name != "_" { output.names.push(name.name); output.values.push(subject) }
            return output
        }
        pattern.literal(literal): {
            output.condition = make_binary_expr(subject, "==", literal.value)
            return output
        }
        pattern.variant(variant): {
            index := program_payload_index(state.payloads, type_name)
            if index < 0 {
                constant := expr.name(name_expr { name: variant.path, inferred_type: option.none })
                if len(variant.args) != 0 { output.error = "payload pattern on scalar enum"; return output }
                output.condition = make_binary_expr(subject, "==", constant)
                return output
            }
            layout := state.payloads[index]
            v := 0
            for v < len(layout.variants) {
                full := layout.symbol + "." + layout.variants[v]
                if variant.path == full || pkg + "." + variant.path == full {
                    tag := expr.member(member_expr { target: std.prelude.box(subject), member: "__variant", inferred_type: option.none })
                    number := expr.int(int_expr { value: std.prelude.to_string(layout.tags[v]), inferred_type: option.none })
                    output.condition = make_binary_expr(tag, "==", number)
                    count := 0
                    if layout.payload_types[v] != "" { count = 1 }
                    if len(variant.args) != count { output.error = "enum pattern payload arity"; return output }
                    if count == 1 {
                        field := "__payload_" + layout.variants[v]
                        payload := expr.member(member_expr { target: std.prelude.box(subject), member: field, inferred_type: option.none })
                        record := state.records[mir_program_record_index(state.records, type_name)]
                        payload_type := record.field_types[mir_program_record_field_index(record, field)]
                        nested := program_pattern_condition(variant.args[0], payload, payload_type, pkg, state)
                        if nested.error != "" { return nested }
                        output.condition = make_binary_expr(output.condition, "&&", nested.condition)
                        output.names = nested.names
                        output.values = nested.values
                    }
                    return output
                }
                v = v + 1
            }
            output.error = "pattern belongs to a different enum: " + variant.path
            return output
        }
    }
}

func program_switch_phi(program_switch_exit[] exits, int binding, program_lower_state initial) program_lower_state {
    state := initial
    operands := int[]()
    i := 0
    for i < len(exits) {
        value := exits[i].result
        if binding >= 0 { value = exits[i].bindings[binding] }
        operands.push(value)
        i = i + 1
    }
    first := operands[0]
    same := true
    i = 1
    for i < len(operands) { if operands[i] != first { same = false }
 i = i + 1 }
    if same { state.expression_value = first; return state }
    type_name := program_expression_type(state, state.signature, first)
    i = 1
    for i < len(operands) {
        if program_expression_type(state, state.signature, operands[i]) != type_name { state.error = "switch branch type mismatch"; return state }
        i = i + 1
    }
    id := state.next_value
    state.next_value = id + 1
    state.instructions.push(mir_program_instruction { op: "phi", result_ids: [id], result_types: [type_name], operands: operands })
    state.expression_value = id
    return state
}

func program_lower_switch(switch_expr value, string pkg, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := initial
    state = program_lower_expression(value.subject.value, pkg, signatures, state)
    if state.error != "" { return state }
    subject_value := state.expression_value
    subject_type := program_expression_type(state, state.signature, subject_value)
    names := state.binding_names
    base := program_copy_values(state.binding_values)
    temporary := "__switch_subject_" + std.prelude.to_string(state.next_value)
    state.binding_names.push(temporary)
    state.binding_values.push(subject_value)
    case_names := state.binding_names
    case_values := program_copy_values(state.binding_values)
    subject := expr.name(name_expr { name: temporary, inferred_type: option.none })
    state = program_new_block(state)
    join := state.created_block
    exits := program_switch_exit[]()
    a := 0
    for a < len(value.arms) {
        match := program_pattern_condition(value.arms[a].pattern, subject, subject_type, pkg, state)
        if match.error != "" { state.error = match.error; return state }
        state = program_lower_expression(match.condition, pkg, signatures, state)
        if state.error != "" { return state }
        condition := state.expression_value
        state = program_new_block(state)
        yes := state.created_block
        state = program_new_block(state)
        next := state.created_block
        state = program_finish_block(state, "branch", [condition], [yes, next])
        state = program_open_block(state, yes)
        state.binding_names = case_names
        state.binding_values = program_copy_values(case_values)
        b := 0
        for b < len(match.names) {
            state = program_lower_expression(match.values[b], pkg, signatures, state)
            if state.error != "" { return state }
            state.binding_names.push(match.names[b])
            state.binding_values.push(state.expression_value)
            b = b + 1
        }
        state = program_lower_expression(value.arms[a].expr, pkg, signatures, state)
        if state.error != "" { return state }
        if !state.terminated {
            if state.expression_value < 0 { state = program_emit_unit(state) }
            outgoing := program_switch_exit { block: state.block_id, result: state.expression_value, bindings: program_copy_values(state.binding_values) }
            exits.push(outgoing)
            state = program_finish_block(state, "jump", int[](), [join])
        }
        state = program_open_block(state, next)
        state.binding_names = case_names
        state.binding_values = program_copy_values(case_values)
        a = a + 1
    }
    state = program_finish_block(state, "unreachable", int[](), int[]())
    state = program_open_block(state, join)
    state.binding_names = names
    state.binding_values = program_copy_values(base)
    if len(exits) == 0 { return program_finish_block(state, "unreachable", int[](), int[]()) }
    i := 1
    for i < len(exits) {
        j := i
        for j > 0 && exits[j - 1].block > exits[j].block { saved := exits[j]; exits[j] = exits[j - 1]; exits[j - 1] = saved; j = j - 1 }
        i = i + 1
    }
    i = 0
    for i < len(base) {
        state = program_switch_phi(exits, i, state)
        if state.error != "" { return state }
        state.binding_values[i] = state.expression_value
        i = i + 1
    }
    return program_switch_phi(exits, -1, state)
}
