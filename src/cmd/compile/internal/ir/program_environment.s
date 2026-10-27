package compile.internal.ir.lower
import ("compile.internal.ast"; "compile.internal.mir"; "std.option"; "std.prelude")

struct program_constant { string symbol; string package_name; expr value }
struct program_environment {
    program_payload_layout[] payloads
    program_constant[] constants
    mir_program_global[] globals
    string error
}

func program_replace_iota(expr value, int index) expr {
    switch value {
        expr.name(name): {
            if name.name == "iota" { return expr.int(int_expr { value: std.prelude.to_string(index), inferred_type: option.some("int") }) }
        }
        expr.binary(binary): {
            left := program_replace_iota(binary.left.value, index)
            right := program_replace_iota(binary.right.value, index)
            return expr.binary(binary_expr { left: std.prelude.box(left), op: binary.op, right: std.prelude.box(right), inferred_type: binary.inferred_type })
        }
        _: (),
    }
    return value
}

func program_collect_environment(source_file source, mir_program_record[] records, mir_program_enum[] enums) program_environment {
    result := program_environment { payloads: program_collect_payloads(source) }
    previous := option[expr].none
    i := 0
    for i < len(source.items) {
        pkg := program_item_package(source, i)
        switch source.items[i] {
            item.const(declaration): {
                if declaration.value.is_some() { previous = declaration.value }
                if previous.is_none() { result.error = "constant initializer is missing: " + declaration.name; return result }
                value := program_replace_iota(previous.unwrap(), declaration.iota_index)
                result.constants.push(program_constant { symbol: pkg + "." + declaration.name, package_name: pkg, value: value })
            }
            item.var(declaration): {
                if declaration.type_name.is_none() { result.error = "global initializer lacks checked type: " + declaration.name; return result }
                type_name := program_record_type(declaration.type_name.unwrap(), pkg, records, enums)
                initializer := ""
                if declaration.value.is_some() { initializer = pkg + ".__global_init_" + declaration.name }
                result.globals.push(mir_program_global { symbol: pkg + "." + declaration.name, type_name: type_name, initializer: initializer })
            }
            _: (),
        }
        i = i + 1
    }
    return result
}

func program_with_global_initializers(source_file initial) source_file {
    output := initial
    i := 0
    for i < len(initial.items) {
        switch initial.items[i] {
            item.var(declaration): {
                if declaration.value.is_some() && declaration.type_name.is_some() {
                    signature := function_sig { name: "__global_init_" + declaration.name, params: param[](), return_type: declaration.type_name }
                    body := block_expr { statements: stmt[](), final_expr: declaration.value, inferred_type: declaration.type_name }
                    function := function_decl { sig: signature, body: option.some(body) }
                    output.items.push(item.function(function))
                    output.item_packages.push(program_item_package(initial, i))
                }
            }
            _: (),
        }
        i = i + 1
    }
    return output
}

func program_environment_global(program_environment environment, string pkg, string name) int {
    i := 0
    for i < len(environment.globals) {
        if name == environment.globals[i].symbol || pkg + "." + name == environment.globals[i].symbol { return i }
        i = i + 1
    }
    return -1
}
func program_environment_constant(program_environment environment, string pkg, string name) int {
    i := 0
    for i < len(environment.constants) {
        if name == environment.constants[i].symbol || pkg + "." + name == environment.constants[i].symbol { return i }
        i = i + 1
    }
    return -1
}
func program_environment_prefix(program_environment environment, string pkg, string path) bool {
    name := path
    i := 0
    for i <= len(path) {
        if i == len(path) || std.prelude.char_at(path, i) == "." {
            name = std.prelude.prelude_slice(path, 0, i)
            if program_environment_global(environment, pkg, name) >= 0 || program_environment_constant(environment, pkg, name) >= 0 { return true }
        }
        i = i + 1
    }
    return false
}
func program_read_global(int index, program_lower_state initial) program_lower_state {
    state := initial
    global := state.environment.globals[index]
    id := state.next_value
    state.next_value = id + 1
    type_name := global.type_name
    state.instructions.push(mir_program_instruction { op: "global_get", result_ids: [id], result_types: [type_name], symbol: global.symbol })
    state.expression_value = id
    return state
}
func program_write_global(int index, int value, program_lower_state initial) program_lower_state {
    state := initial
    global := state.environment.globals[index]
    id := state.next_value
    state.next_value = id + 1
    state.instructions.push(mir_program_instruction { op: "global_set", result_ids: [id], result_types: ["()"], operands: [value], symbol: global.symbol })
    state.expression_value = id
    return state
}

func program_update_place(string root, program_store_step[] steps, int value, string pkg, program_lower_state initial) program_lower_state {
    state := initial
    rhs := value
    i := len(steps)
    for i > 0 {
        i = i - 1
        step := steps[i]
        if step.kind == "record" {
            id := state.next_value
            state.next_value = id + 1
            container := step.container
            type_name := step.type_name
            state.instructions.push(mir_program_instruction { op: "record_set", result_ids: [id], result_types: [type_name], operands: [container, rhs], symbol: type_name, integer_value: step.selector })
            rhs = id
        } else {
            container := step.container
            selector := step.selector
            state = program_emit_array(state, "array_set", step.type_name, step.type_name, [container, selector, rhs])
            rhs = state.expression_value
        }
    }
    binding := program_binding_index(state, root)
    if binding >= 0 { state.binding_values[binding] = rhs; state.expression_value = rhs; return state }
    global := program_environment_global(state.environment, pkg, root)
    if global >= 0 { return program_write_global(global, rhs, state) }
    state.error = "store to undefined binding: " + root
    return state
}

func program_array_method(member_expr member, expr[] arguments, string pkg, mir_program_function[] signatures, program_lower_state initial) program_lower_state {
    state := initial
    if member.member == "len" {
        args := expr[]()
        args.push(member.target.value)
        callee := expr.name(name_expr { name: "len", inferred_type: option.none })
        call := expr.call(call_expr { callee: std.prelude.box(callee), args: args, inferred_type: option.none, resolved_callee: option.none, type_args: string[]() })
        if len(arguments) != 0 { state.error = "len method takes no arguments"; return state }
        return program_lower_expression(call, pkg, signatures, state)
    }
    state.store_root = ""
    state.store_steps = program_store_step[]()
    state = program_prepare_store(member.target.value, pkg, signatures, state)
    if state.error != "" { return state }
    root := state.store_root
    steps := state.store_steps
    target := state.expression_value
    type_name := program_expression_type(state, state.signature, target)
    if mir_program_array_element(type_name) == "" { state.error = "array method requires an array"; return state }
    operands := [target];
    i := 0
    for i < len(arguments) {
        state = program_lower_expression(arguments[i], pkg, signatures, state)
        if state.error != "" { return state }
        operands.push(state.expression_value)
        i = i + 1
    }
    if member.member == "push" {
        if len(arguments) != 1 { state.error = "push takes one argument"; return state }
        state = program_emit_array(state, "array_append", type_name, type_name, operands)
    } else {
        if len(arguments) != 2 { state.error = "set takes two arguments"; return state }
        state = program_emit_array(state, "array_set", type_name, type_name, operands)
    }
    state = program_update_place(root, steps, state.expression_value, pkg, state)
    if state.error != "" { return state }
    return program_emit_unit(state)
}
