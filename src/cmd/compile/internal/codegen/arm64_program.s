package compile.internal

func arm64_fail(string error) amd64_program_result {
    return amd64_program_result { assembly: "", error: error }
}

func arm64_function_name(int index) string {
    return "s_native_fn_" + amd64_integer(index)
}

func arm64_int_arg_register(int index) string {
    if index == 0 { return "x0" }
    if index == 1 { return "x1" }
    if index == 2 { return "x2" }
    if index == 3 { return "x3" }
    if index == 4 { return "x4" }
    if index == 5 { return "x5" }
    if index == 6 { return "x6" }
    return "x7"
}

func arm64_slot_offset(function_ssa_value[] values, int id) int {
    return (ssa_value_index(values, id) + 1) * 8
}

func arm64_emit_load_slot(function_ssa_value[] values, int id, string register_name, string scratch_register) string {
    offset := arm64_slot_offset(values, id)
    if offset <= 255 {
        return "  ldur " + register_name + ", [x29, #-" + amd64_integer(offset) + "]\n"
    }
    return "  sub " + scratch_register + ", x29, #" + amd64_integer(offset) + "\n  ldr " + register_name + ", [" + scratch_register + "]\n"
}

func arm64_emit_store_slot(function_ssa_value[] values, int id, string register_name, string scratch_register) string {
    offset := arm64_slot_offset(values, id)
    if offset <= 255 {
        return "  stur " + register_name + ", [x29, #-" + amd64_integer(offset) + "]\n"
    }
    return "  sub " + scratch_register + ", x29, #" + amd64_integer(offset) + "\n  str " + register_name + ", [" + scratch_register + "]\n"
}

func arm64_emit_load_scratch(int index, string register_name, string scratch_register) string {
    offset := (index + 1) * 8
    if offset <= 255 {
        return "  ldur " + register_name + ", [x29, #-" + amd64_integer(offset) + "]\n"
    }
    return "  sub " + scratch_register + ", x29, #" + amd64_integer(offset) + "\n  ldr " + register_name + ", [" + scratch_register + "]\n"
}

func arm64_emit_store_scratch(int index, string register_name, string scratch_register) string {
    offset := (index + 1) * 8
    if offset <= 255 {
        return "  stur " + register_name + ", [x29, #-" + amd64_integer(offset) + "]\n"
    }
    return "  sub " + scratch_register + ", x29, #" + amd64_integer(offset) + "\n  str " + register_name + ", [" + scratch_register + "]\n"
}

func arm64_call_target(function_ssa_program program, string caller, int block_id, int value_id) int {
    i := 0
    for i < len(program.calls) {
        edge := program.calls[i]
        if edge.caller == caller && edge.block_id == block_id && edge.value_id == value_id {
            return ssa_function_index(program.functions, edge.callee)
        }
        i = i + 1
    }
    return -1
}

func arm64_validate_program(function_ssa_program program) string {
    error := verify_ssa_program(program)
    if error != "" { return "arm64: " + error }
    f := 0
    for f < len(program.functions) {
        function_data := program.functions[f]
        if len(function_data.result_types) > 1 { return "arm64: multiple results unsupported: " + function_data.symbol }
        if len(function_data.result_types) == 1 && !ssa_type_supported(function_data.result_types[0], program.records) { return "arm64: unsupported result type" }
        p := 0
        for p < len(function_data.parameter_types) {
            if !ssa_type_supported(function_data.parameter_types[p], program.records) { return "arm64: unsupported parameter type" }
            count := 0
            b := 0
            for b < len(function_data.blocks) {
                v := 0
                for v < len(function_data.blocks[b].values) {
                    value := function_data.blocks[b].values[v]
                    if value.op == "param" && value.parameter_index == p { count = count + 1 }
                    v = v + 1
                }
                b = b + 1
            }
            if !ssa_function_external(function_data) && count != 1 { return "arm64: missing or duplicate parameter" }
            p = p + 1
        }
        b := 0
        for b < len(function_data.blocks) {
            v := 0
            for v < len(function_data.blocks[b].values) {
                value := function_data.blocks[b].values[v]
                op := value.op
                supported := op == "param" || op == "phi" || op == "const_unit" || op == "const_bool" || op == "const_int" || op == "copy" || op == "add" || op == "sub" || op == "mul" || op == "div" || op == "mod" || op == "bit_and" || op == "bit_or" || op == "bit_xor" || op == "shl" || op == "shr" || op == "bool_to_int" || op == "cmp_eq" || op == "cmp_ne" || op == "cmp_lt" || op == "cmp_le" || op == "cmp_gt" || op == "cmp_ge" || op == "call"
                if !supported { return "arm64: unsupported operation: " + op }
                if !ssa_type_supported(value.type_name, program.records) && !((op == "call") && value.type_name == "void") { return "arm64: unsupported value type" }
                v = v + 1
            }
            b = b + 1
        }
        f = f + 1
    }
    return ""
}

func arm64_function_values(function_ssa_function function_data) function_ssa_value[] {
    values := function_ssa_value[]()
    b := 0
    for b < len(function_data.blocks) {
        v := 0
        for v < len(function_data.blocks[b].values) { values = append(values, function_data.blocks[b].values[v]); v = v + 1 }
        b = b + 1
    }
    return values
}

func arm64_emit_call_with_values(function_ssa_program program, function_ssa_function function_data, function_ssa_value value, function_ssa_value[] values) string {
    stack_count := len(value.operands) - 8
    if stack_count < 0 { stack_count = 0 }
    text := ""
    stack_bytes := stack_count * 8
    if stack_bytes % 16 != 0 { stack_bytes = stack_bytes + 8 }
    if stack_bytes > 0 { text = text + "  sub sp, sp, #" + amd64_integer(stack_bytes) + "\n" }
    a := 8
    for a < len(value.operands) {
        text = text + arm64_emit_load_slot(values, value.operands[a], "x9", "x10")
        text = text + "  str x9, [sp, #" + amd64_integer((a - 8) * 8) + "]\n"
        a = a + 1
    }
    a = 0
    for a < len(value.operands) && a < 8 {
        text = text + arm64_emit_load_slot(values, value.operands[a], arm64_int_arg_register(a), "x9")
        a = a + 1
    }
    target := arm64_call_target(program, function_data.symbol, value.block_id, value.id)
    text = text + "  bl " + arm64_function_name(target) + "\n"
    if stack_bytes > 0 { text = text + "  add sp, sp, #" + amd64_integer(stack_bytes) + "\n" }
    if value.type_name != "void" {
        text = text + arm64_emit_store_slot(values, value.id, "x0", "x9")
    }
    return text
}

func arm64_emit_value_with_values(function_ssa_program program, int function_index, int position, function_ssa_value[] values) string {
    function_data := program.functions[function_index]
    value := values[position]
    op := value.op
    if op == "param" || op == "phi" { return "" }
    if op == "call" { return arm64_emit_call_with_values(program, function_data, value, values) }
    if op == "const_unit" { return arm64_emit_store_slot(values, value.id, "xzr", "x9") }
    if op == "const_bool" || op == "const_int" {
        text := "  mov x0, #" + amd64_integer(value.integer_value) + "\n"
        return text + arm64_emit_store_slot(values, value.id, "x0", "x9")
    }
    if op == "bool_to_int" || op == "copy" {
        text := arm64_emit_load_slot(values, value.operands[0], "x0", "x9")
        return text + arm64_emit_store_slot(values, value.id, "x0", "x9")
    }
    if op == "cmp_eq" || op == "cmp_ne" || op == "cmp_lt" || op == "cmp_le" || op == "cmp_gt" || op == "cmp_ge" {
        condition := "eq"
        if op == "cmp_ne" { condition = "ne" }
        if op == "cmp_lt" { condition = "lt" }
        if op == "cmp_le" { condition = "le" }
        if op == "cmp_gt" { condition = "gt" }
        if op == "cmp_ge" { condition = "ge" }
        text := arm64_emit_load_slot(values, value.operands[0], "x0", "x9")
        text = text + arm64_emit_load_slot(values, value.operands[1], "x1", "x9")
        text = text + "  cmp x0, x1\n  cset x0, " + condition + "\n"
        return text + arm64_emit_store_slot(values, value.id, "x0", "x9")
    }
    text := arm64_emit_load_slot(values, value.operands[0], "x0", "x9")
    text = text + arm64_emit_load_slot(values, value.operands[1], "x1", "x9")
    if op == "add" { text = text + "  add x0, x0, x1\n" }
    if op == "sub" { text = text + "  sub x0, x0, x1\n" }
    if op == "mul" { text = text + "  mul x0, x0, x1\n" }
    if op == "bit_and" { text = text + "  and x0, x0, x1\n" }
    if op == "bit_or" { text = text + "  orr x0, x0, x1\n" }
    if op == "bit_xor" { text = text + "  eor x0, x0, x1\n" }
    if op == "shl" { text = text + "  and x1, x1, #63\n  lslv x0, x0, x1\n" }
    if op == "shr" { text = text + "  and x1, x1, #63\n  asrv x0, x0, x1\n" }
    if op == "div" || op == "mod" {
        label := ".Ls_native_div_" + amd64_integer(function_index) + "_" + amd64_integer(position)
        text = text + "  cbz x1, .Ls_native_divzero\n  sdiv x2, x0, x1\n"
        if op == "mod" {
            text = text + "  msub x0, x2, x1, x0\n"
        } else {
            text = text + "  mov x0, x2\n"
        }
        text = text + "  b " + label + "_done\n" + label + "_done:\n"
    }
    return text + arm64_emit_store_slot(values, value.id, "x0", "x9")
}

func arm64_block_label(int function_index, int block_id) string {
    return ".Ls_native_f_" + amd64_integer(function_index) + "_b_" + amd64_integer(block_id)
}

func arm64_emit_edge(function_ssa_function function_data, function_ssa_value[] values, int function_index, int from, int target, int occurrence) string {
    destination := function_data.blocks[ssa_block_index(function_data.blocks, target)]
    predecessor := -1
    seen := 0
    i := 0
    for i < len(destination.predecessors) {
        if destination.predecessors[i] == from {
            if seen == occurrence { predecessor = i; break }
            seen = seen + 1
        }
        i = i + 1
    }
    text := ""
    count := 0
    i = 0
    for i < len(destination.values) {
        phi := destination.values[i]
        if phi.op == "phi" {
            scratch_index := len(values) + count
            text = text + arm64_emit_load_slot(values, phi.operands[predecessor], "x0", "x9")
            text = text + arm64_emit_store_scratch(scratch_index, "x0", "x9")
            count = count + 1
        }
        i = i + 1
    }
    count = 0
    i = 0
    for i < len(destination.values) {
        phi := destination.values[i]
        if phi.op == "phi" {
            scratch_index := len(values) + count
            text = text + arm64_emit_load_scratch(scratch_index, "x0", "x9")
            text = text + arm64_emit_store_slot(values, phi.id, "x0", "x9")
            count = count + 1
        }
        i = i + 1
    }
    return text + "  b " + arm64_block_label(function_index, target) + "\n"
}

func arm64_emit_values_range(function_ssa_program program, int index, function_ssa_value[] values, int start, int end) string {
    if start >= end { return "" }
    if end - start == 1 {
        if values[start].op == "phi" { return "" }
        return arm64_emit_value_with_values(program, index, start, values)
    }
    middle := start + (end - start) / 2
    left := arm64_emit_values_range(program, index, values, start, middle)
    right := arm64_emit_values_range(program, index, values, middle, end)
    return left + right
}

func arm64_emit_blocks_range(function_ssa_program program, int index, function_ssa_value[] values, int start, int end, int position) string {
    if start >= end { return "" }
    function_data := program.functions[index]
    if end - start == 1 {
        b := start
        block := function_data.blocks[b]
        text := arm64_block_label(index, block.id) + ":\n"
        text = text + arm64_emit_values_range(program, index, values, position, position + len(block.values))
        if block.terminator == "return" {
            if len(block.terminator_values) == 1 {
                text = text + arm64_emit_load_slot(values, block.terminator_values[0], "x0", "x9")
            } else {
                text = text + "  mov x0, #0\n"
            }
            text = text + "  add sp, sp, #" + amd64_integer((((len(values) + 16) * 8 + 15) / 16) * 16) + "\n  ldp x29, x30, [sp], #16\n  ret\n"
        } else if block.terminator == "jump" {
            text = text + arm64_emit_edge(function_data, values, index, block.id, block.successors[0], 0)
        } else if block.terminator == "branch" {
            otherwise := ".Ls_native_f_" + amd64_integer(index) + "_edge_" + amd64_integer(b)
            text = text + arm64_emit_load_slot(values, block.terminator_values[0], "x0", "x9")
            text = text + "  cbz x0, " + otherwise + "\n"
            text = text + arm64_emit_edge(function_data, values, index, block.id, block.successors[0], 0)
            occurrence := 0
            if block.successors[0] == block.successors[1] { occurrence = 1 }
            text = text + otherwise + ":\n" + arm64_emit_edge(function_data, values, index, block.id, block.successors[1], occurrence)
        } else {
            text = text + "  brk #0\n"
        }
        return text
    }
    middle := start + (end - start) / 2
    middle_position := position
    b := start
    for b < middle { middle_position = middle_position + len(function_data.blocks[b].values); b = b + 1 }
    left := arm64_emit_blocks_range(program, index, values, start, middle, position)
    right := arm64_emit_blocks_range(program, index, values, middle, end, middle_position)
    return left + right
}

func arm64_emit_function(function_ssa_program program, int index) string {
    function_data := program.functions[index]
    values := arm64_function_values(function_data)
    name := arm64_function_name(index)
    frame_size := (((len(values) + 16) * 8 + 15) / 16) * 16
    text := ".globl " + name + "\n.type " + name + ", @function\n" + name + ":\n  stp x29, x30, [sp, #-16]!\n  mov x29, sp\n"
    if frame_size > 0 { text = text + "  sub sp, sp, #" + amd64_integer(frame_size) + "\n" }
    v := 0
    for v < len(values) {
        value := values[v]
        if value.op == "param" {
            if value.parameter_index < 8 {
                text = text + arm64_emit_store_slot(values, value.id, arm64_int_arg_register(value.parameter_index), "x9")
            } else {
                stack_offset := 16 + (value.parameter_index - 8) * 8
                text = text + "  ldr x0, [x29, #" + amd64_integer(stack_offset) + "]\n"
                text = text + arm64_emit_store_slot(values, value.id, "x0", "x9")
            }
        }
        v = v + 1
    }
    text = text + "  b " + arm64_block_label(index, function_data.entry_block) + "\n"
    text = text + arm64_emit_blocks_range(program, index, values, 0, len(function_data.blocks), 0)
    return text + ".size " + name + ", .-" + name + "\n"
}

func arm64_emit_functions_range(function_ssa_program program, int start, int end) string {
    if start >= end { return "" }
    if end - start == 1 { return arm64_emit_function(program, start) }
    middle := start + (end - start) / 2
    left := arm64_emit_functions_range(program, start, middle)
    right := arm64_emit_functions_range(program, middle, end)
    return left + right
}

func emit_function_ssa_arm64(function_ssa_program program) amd64_program_result {
    error := arm64_validate_program(program)
    if error != "" { return arm64_fail(error) }
    f := 0
    for f < len(program.functions) {
        if ssa_function_external(program.functions[f]) { return arm64_fail("unresolved external function: " + program.functions[f].symbol) }
        f = f + 1
    }
    text := ".text\n" + arm64_emit_functions_range(program, 0, len(program.functions))
    entry_index := ssa_function_index(program.functions, program.entry_symbol)
    text = text + ".globl s_native_entry\n.type s_native_entry, @function\ns_native_entry:\n  b " + arm64_function_name(entry_index) + "\n.size s_native_entry, .-s_native_entry\n"
    text = text + ".Ls_native_divzero:\n  mov x0, #86\n  mov x8, #93\n  svc #0\n  brk #0\n"
    text = text + ".section .note.GNU-stack,\"\",@progbits\n"
    return amd64_program_result { assembly: text, error: "" }
}

func arm64_executable_startup(function_ssa_program program) amd64_program_result {
    if ssa_function_index(program.functions, program.entry_symbol) < 0 {
        return arm64_fail("missing entry function: " + program.entry_symbol)
    }
    text := ".text\n.globl _start\n.type _start, @function\n_start:\n"
    text = text + "  ldr x0, [sp]\n  cmp x0, #2\n  b.lt .Ls_native_arg_error\n"
    text = text + "  ldr x1, [sp, #16]\n  mov x0, #0\n  mov x2, #1\n"
    text = text + "  ldrb w3, [x1]\n  cmp w3, #45\n  b.ne .Ls_native_parse_loop\n"
    text = text + "  mov x2, #-1\n  add x1, x1, #1\n"
    text = text + ".Ls_native_parse_loop:\n"
    text = text + "  ldrb w3, [x1]\n  cbz w3, .Ls_native_parse_done\n"
    text = text + "  cmp w3, #48\n  b.lt .Ls_native_arg_error\n  cmp w3, #57\n  b.gt .Ls_native_arg_error\n"
    text = text + "  sub w3, w3, #48\n  mov x4, #10\n  mul x0, x0, x4\n  add x0, x0, x3\n  add x1, x1, #1\n  b .Ls_native_parse_loop\n"
    text = text + ".Ls_native_parse_done:\n"
    text = text + "  cmp x2, #1\n  b.eq .Ls_native_call_entry\n  neg x0, x0\n"
    text = text + ".Ls_native_call_entry:\n  bl s_native_entry\n  mov x8, #93\n  svc #0\n"
    text = text + ".Ls_native_arg_error:\n  mov x0, #2\n  mov x8, #93\n  svc #0\n  brk #0\n.size _start, .-_start\n"
    return amd64_program_result { assembly: text, error: "" }
}
