package compile.internal

extern "intrinsic" func __host_byte_at(string source, int index) int


// This: is instruction selection, not an interpreter or a C source producer.
// GNU as encodes these instructions and ELF relocations; GNU ld links them.
struct amd64_program_result {
    string assembly
    string error
}

func amd64_fail(string error) amd64_program_result {
    return amd64_program_result { assembly: "", error: error }
}

func amd64_integer(int value) string {
    if value == 0 { return "0" }
    negative := value < 0
    remaining := value
    if remaining > 0 { remaining = 0 - remaining }
    text := ""
    for remaining < 0 {
        digit := 0 - (remaining % 10)
        ch := "0"
        if digit == 1 { ch = "1" }
        if digit == 2 { ch = "2" }
        if digit == 3 { ch = "3" }
        if digit == 4 { ch = "4" }
        if digit == 5 { ch = "5" }
        if digit == 6 { ch = "6" }
        if digit == 7 { ch = "7" }
        if digit == 8 { ch = "8" }
        if digit == 9 { ch = "9" }
        text = ch + text
        remaining = remaining / 10
    }
    if negative { return "-" + text }
    return text
}

func amd64_function_name(int index) string {
    // Source symbols are never inserted into assembler identifiers.
    return "s_native_fn_" + amd64_integer(index)
}

func amd64_register(int index) string {
    if index == 0 { return "%rdi" }
    if index == 1 { return "%rsi" }
    if index == 2 { return "%rdx" }
    if index == 3 { return "%rcx" }
    if index == 4 { return "%r8" }
    return "%r9"
}

func amd64_slot(function_ssa_value[] values, int id) string {
    // Positions, not arbitrary SSA: IDs, determine the frame size and offsets.
    return "-" + amd64_integer((ssa_value_index(values, id) + 1) * 8) + "(%rbp)"
}

func amd64_call_target(function_ssa_program program, string caller, int block_id, int value_id) int {
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

func amd64_validate_program(function_ssa_program program) string {
    error := verify_ssa_program(program)
    if error != "" { return "amd64: " + error }
    f := 0
    for f < len(program.functions) {
        function_data := program.functions[f]
        if len(function_data.result_types) > 1 { return "amd64: multiple results unsupported: " + function_data.symbol }
        if len(function_data.result_types) == 1 && !ssa_type_supported(function_data.result_types[0], program.records) { return "amd64: unsupported result type" }
        p := 0
        for p < len(function_data.parameter_types) {
            if !ssa_type_supported(function_data.parameter_types[p], program.records) { return "amd64: unsupported parameter type" }
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
            if !ssa_function_external(function_data) && count != 1 { return "amd64: missing or duplicate parameter" }
            p = p + 1
        }
        b := 0
        for b < len(function_data.blocks) {
            v := 0
            for v < len(function_data.blocks[b].values) {
                value := function_data.blocks[b].values[v]
                op := value.op
                supported := op == "reference_new" || op == "reference_get" || op == "reference_set" || op == "reference_readonly" || op == "global_get" || op == "global_set" || op == "native_intrinsic" || op == "string_byte_at" || op == "string_char_at" || op == "string_slice" || op == "string_eq" || op == "string_ne" || op == "string_lt" || op == "string_le" || op == "string_gt" || op == "string_ge" || op == "const_string" || op == "string_concat" || op == "string_len" || ssa_is_scalar_operation(op) || op == "param" || op == "phi" || op == "const_int" || op == "const_unit" || op == "copy" || op == "add" || op == "sub" || op == "mul" || op == "div" || op == "mod" || op == "bit_and" || op == "bit_or" || op == "bit_xor" || op == "shl" || op == "shr" || op == "call" || op == "record_new" || op == "record_get" || op == "record_set" || op == "array_new" || op == "array_get" || op == "array_len" || op == "array_append" || op == "array_set"
                if !supported { return "amd64: unsupported operation: " + op }
                if !ssa_type_supported(value.type_name, program.records) && !((op == "call" || op == "native_intrinsic") && value.type_name == "void") { return "amd64: unsupported value type" }
                v = v + 1
            }
            b = b + 1
        }
        f = f + 1
    }
    return ""
}

func amd64_function_values(function_ssa_function function_data) function_ssa_value[] {
    values := function_ssa_value[]()
    b := 0
    for b < len(function_data.blocks) {
        v := 0
        for v < len(function_data.blocks[b].values) { values = append(values, function_data.blocks[b].values[v]); v = v + 1 }
        b = b + 1
    }
    return values
}

func amd64_emit_call(function_ssa_program program, function_ssa_function function_data, function_ssa_value value) string {
    return amd64_emit_call_with_values(program, function_data, value, amd64_function_values(function_data))
}

func amd64_emit_call_with_values(function_ssa_program program, function_ssa_function function_data, function_ssa_value value, function_ssa_value[] values) string {
    stack_count := len(value.operands) - 6
    if stack_count < 0 { stack_count = 0 }
    text := ""
    // At this point rsp is 16-byte aligned. Pad before pushing arguments so
    // argument seven remains at 16(%rbp) in the callee, including odd counts.
    padding := stack_count % 2
    if padding != 0 { text = text + "  subq $8, %rsp\n" }
    a := len(value.operands) - 1
    for a >= 6 {
        text = text + "  pushq " + amd64_slot(values, value.operands[a]) + "\n"
        a = a - 1
    }
    a = 0
    for a < len(value.operands) && a < 6 {
        text = text + "  movq " + amd64_slot(values, value.operands[a]) + ", " + amd64_register(a) + "\n"
        a = a + 1
    }
    target := amd64_call_target(program, function_data.symbol, value.block_id, value.id)
    text = text + "  call " + amd64_function_name(target) + "\n"
    cleanup := (stack_count + padding) * 8
    if cleanup > 0 { text = text + "  addq $" + amd64_integer(cleanup) + ", %rsp\n" }
    if value.type_name != "void" { text = text + "  movq %rax, " + amd64_slot(values, value.id) + "\n" }
    return text
}

func amd64_emit_value(function_ssa_program program, int function_index, int position) string {
    return amd64_emit_value_with_values(program, function_index, position, amd64_function_values(program.functions[function_index]))
}

func amd64_emit_value_with_values(function_ssa_program program, int function_index, int position, function_ssa_value[] values) string {
    function_data := program.functions[function_index]
    value := values[position]
    op := value.op
    if op == "param" { return "" }
    if op == "global_get" || op == "global_set" { return amd64_emit_global(program, values, value) }
    if op == "native_intrinsic" { return amd64_emit_native_intrinsic(values, value, function_index, position) }
    slot := amd64_slot(values, value.id)
    if op == "reference_new" {
        return "  movq $8, %rdi\n  call .Ls_native_alloc\n  movq " + amd64_slot(values, value.operands[0]) + ", %r10\n  movq %r10, (%rax)\n  movq %rax, " + slot + "\n"
    }
    if op == "reference_get" || op == "reference_readonly" {
        text := "  movq " + amd64_slot(values, value.operands[0]) + ", %rax\n"
        if op == "reference_get" { text = text + "  movq (%rax), %rax\n" }
        return text + "  movq %rax, " + slot + "\n"
    }
    if op == "reference_set" {
        return "  movq " + amd64_slot(values, value.operands[0]) + ", %rax\n  movq " + amd64_slot(values, value.operands[1]) + ", %r10\n  movq %r10, (%rax)\n  movq $0, " + slot + "\n"
    }
    if op == "string_byte_at" || op == "string_char_at" || op == "string_slice" { return amd64_emit_string_access(values, value, function_index, position) }
    if op == "string_eq" || op == "string_ne" || op == "string_lt" || op == "string_le" || op == "string_gt" || op == "string_ge" || op == "const_string" || op == "string_concat" || op == "string_len" { return amd64_emit_string(values, value, function_index, position) }
    if op == "const_unit" { return "  movq $0, " + slot + "\n" }
    if op == "const_bool" { return "  movq $" + amd64_integer(value.integer_value) + ", " + slot + "\n" }
    if op == "bool_to_int" { return "  movq " + amd64_slot(values, value.operands[0]) + ", %rax\n  movq %rax, " + slot + "\n" }
    if op == "cmp_eq" || op == "cmp_ne" || op == "cmp_lt" || op == "cmp_le" || op == "cmp_gt" || op == "cmp_ge" {
        instruction := "sete"
        if op == "cmp_ne" { instruction = "setne" }
        if op == "cmp_lt" { instruction = "setl" }
        if op == "cmp_le" { instruction = "setle" }
        if op == "cmp_gt" { instruction = "setg" }
        if op == "cmp_ge" { instruction = "setge" }
        return "  movq " + amd64_slot(values, value.operands[0]) + ", %rax\n  movq " + amd64_slot(values, value.operands[1]) + ", %r10\n  cmpq %r10, %rax\n  " + instruction + " %al\n  movzbq %al, %rax\n  movq %rax, " + slot + "\n"
    }
    if op == "const_int" {
        return "  movabsq $" + amd64_integer(value.integer_value) + ", %rax\n  movq %rax, " + slot + "\n"
    }
    if op == "call" { return amd64_emit_call_with_values(program, function_data, value, values) }
    if op == "array_new" || op == "array_get" || op == "array_len" || op == "array_append" || op == "array_set" { return amd64_emit_array_with_values(program, function_index, position, values) }
    if op == "record_new" {
        record := program.records[ssa_record_index(program.records, value.symbol)]
        size := len(record.field_names) * 8
        if size == 0 { size = 8 }
        text := "  movq $" + amd64_integer(size) + ", %rdi\n  call .Ls_native_alloc\n  movq %rax, " + slot + "\n"
        i := 0
        for i < len(value.operands) {
            field := ssa_record_field_index(record, value.field_names[i])
            text = text + "  movq " + amd64_slot(values, value.operands[i]) + ", %r10\n  movq %r10, " + amd64_integer(field * 8) + "(%rax)\n"
            i = i + 1
        }
        return text
    }
    if op == "record_set" {
        record := program.records[ssa_record_index(program.records, value.symbol)]
        size := len(record.field_names) * 8
        if size == 0 { size = 8 }
        done := ".Ls_record_set_" + amd64_integer(function_index) + "_" + amd64_integer(position)
        text := "  movq $" + amd64_integer(size) + ", %rdi\n  call .Ls_native_alloc\n  movq %rax, " + slot + "\n  movq " + amd64_slot(values, value.operands[0]) + ", %r8\n  testq %r8, %r8\n  je " + done + "\n"
        loop_var_2 := 0
        for loop_var_2 < len(record.field_names) {
            offset := amd64_integer(loop_var_2 * 8)
            text = text + "  movq " + offset + "(%r8), %r10\n  movq %r10, " + offset + "(%rax)\n"
            loop_var_2 = loop_var_2 + 1
        }
        return text + done + ":\n  movq " + amd64_slot(values, value.operands[1]) + ", %r10\n  movq %r10, " + amd64_integer(value.integer_value * 8) + "(%rax)\n"
    }
    if op == "record_get" {
        done := ".Ls_record_get_" + amd64_integer(function_index) + "_" + amd64_integer(position)
        return "  movq " + amd64_slot(values, value.operands[0]) + ", %rax\n  testq %rax, %rax\n  je " + done + "\n  movq " + amd64_integer(value.integer_value * 8) + "(%rax), %rax\n" + done + ":\n  movq %rax, " + slot + "\n"
    }
    text := "  movq " + amd64_slot(values, value.operands[0]) + ", %rax\n"
    if op == "copy" { return text + "  movq %rax, " + slot + "\n" }
    text = text + "  movq " + amd64_slot(values, value.operands[1]) + ", %r10\n"
    if op == "add" { text = text + "  addq %r10, %rax\n" }
    if op == "sub" { text = text + "  subq %r10, %rax\n" }
    if op == "mul" { text = text + "  imulq %r10, %rax\n" }
    if op == "bit_and" { text = text + "  andq %r10, %rax\n" }
    if op == "bit_or" { text = text + "  orq %r10, %rax\n" }
    if op == "bit_xor" { text = text + "  xorq %r10, %rax\n" }
    // Hardware counts use the low six bits; right shift preserves the sign.
    if op == "shl" { text = text + "  movq %r10, %rcx\n  shlq %cl, %rax\n" }
    if op == "shr" { text = text + "  movq %r10, %rcx\n  sarq %cl, %rax\n" }
    if op == "div" || op == "mod" {
        label := ".Ls_native_div_" + amd64_integer(function_index) + "_" + amd64_integer(position)
        text = text + "  testq %r10, %r10\n  je .Ls_native_divzero\n"
            + "  cmpq $-1, %r10\n  jne " + label + "_normal\n"
            + "  movabsq $-9223372036854775808, %r11\n  cmpq %r11, %rax\n  jne " + label + "_normal\n"
            + "  xorl %edx, %edx\n  jmp " + label + "_done\n"
            + label + "_normal:\n  cqto\n  idivq %r10\n" + label + "_done:\n"
        if op == "mod" { text = text + "  movq %rdx, %rax\n" }
    }
    return text + "  movq %rax, " + slot + "\n"
}

func amd64_block_label(int function_index, int block_id) string {
    return ".Ls_native_f_" + amd64_integer(function_index) + "_b_" + amd64_integer(block_id)
}

func amd64_emit_edge(function_ssa_function function_data, function_ssa_value[] values, int function_index, int from, int target, int occurrence) string {
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
            scratch := "-" + amd64_integer((len(values) + count + 1) * 8) + "(%rbp)"
            text = text + "  movq " + amd64_slot(values, phi.operands[predecessor]) + ", %rax\n  movq %rax, " + scratch + "\n"
            count = count + 1
        }
        i = i + 1
    }
    count = 0
    i = 0
    for i < len(destination.values) {
        phi := destination.values[i]
        if phi.op == "phi" {
            scratch := "-" + amd64_integer((len(values) + count + 1) * 8) + "(%rbp)"
            text = text + "  movq " + scratch + ", %rax\n  movq %rax, " + amd64_slot(values, phi.id) + "\n"
            count = count + 1
        }
        i = i + 1
    }
    return text + "  jmp " + amd64_block_label(function_index, target) + "\n"
}

// Balanced concatenation bounds retained text under the native bump arena.
// Keep leaf emission and its absolute value/block positions unchanged.
func amd64_emit_values_range(function_ssa_program program, int index, function_ssa_value[] values, int start, int end) string {
    if start >= end { return "" }
    if end - start == 1 {
        if values[start].op == "phi" { return "" }
        return amd64_emit_value_with_values(program, index, start, values)
    }
    middle := start + (end - start) / 2
    left := amd64_emit_values_range(program, index, values, start, middle)
    right := amd64_emit_values_range(program, index, values, middle, end)
    return left + right
}

func amd64_emit_blocks_range(function_ssa_program program, int index, function_ssa_value[] values, int start, int end, int position) string {
    if start >= end { return "" }
    function_data := program.functions[index]
    if end - start == 1 {
        b := start
        block := function_data.blocks[b]
        text := amd64_block_label(index, block.id) + ":\n"
        text = text + amd64_emit_values_range(program, index, values, position, position + len(block.values))
        if block.terminator == "return" {
            if len(block.terminator_values) == 1 { text = text + "  movq " + amd64_slot(values, block.terminator_values[0]) + ", %rax\n" }
            else { text = text + "  xorl %eax, %eax\n" }
            text = text + "  leave\n  ret\n"
        } else if block.terminator == "jump" { text = text + amd64_emit_edge(function_data, values, index, block.id, block.successors[0], 0) }
        else if block.terminator == "branch" {
            otherwise := ".Ls_native_f_" + amd64_integer(index) + "_edge_" + amd64_integer(b)
            text = text + "  cmpq $0, " + amd64_slot(values, block.terminator_values[0]) + "\n  je " + otherwise + "\n"
            text = text + amd64_emit_edge(function_data, values, index, block.id, block.successors[0], 0)
            occurrence := 0
            if block.successors[0] == block.successors[1] { occurrence = 1 }
            text = text + otherwise + ":\n" + amd64_emit_edge(function_data, values, index, block.id, block.successors[1], occurrence)
        } else { text = text + "  ud2\n" }
        return text
    }
    middle := start + (end - start) / 2
    middle_position := position
    b := start
    for b < middle { middle_position = middle_position + len(function_data.blocks[b].values); b = b + 1 }
    left := amd64_emit_blocks_range(program, index, values, start, middle, position)
    right := amd64_emit_blocks_range(program, index, values, middle, end, middle_position)
    return left + right
}

func amd64_emit_function(function_ssa_program program, int index) string {
    function_data := program.functions[index]
    values := amd64_function_values(function_data)
    name := amd64_function_name(index)
    frame_size := ((len(values) * 16 + 15) / 16) * 16
    text := ".globl " + name + "\n.type " + name + ", @function\n" + name + ":\n  pushq %rbp\n  movq %rsp, %rbp\n"
    if frame_size > 0 { text = text + "  subq $" + amd64_integer(frame_size) + ", %rsp\n" }
    v := 0
    for v < len(values) {
        value := values[v]
        if value.op == "param" {
            source := amd64_register(value.parameter_index)
            if value.parameter_index >= 6 {
                source = amd64_integer(16 + (value.parameter_index - 6) * 8) + "(%rbp)"
                text = text + "  movq " + source + ", %rax\n"
                source = "%rax"
            }
            text = text + "  movq " + source + ", " + amd64_slot(values, value.id) + "\n"
        }
        v = v + 1
    }
    text = text + "  jmp " + amd64_block_label(index, function_data.entry_block) + "\n"
    text = text + amd64_emit_blocks_range(program, index, values, 0, len(function_data.blocks), 0)
    return text + ".size " + name + ", .-" + name + "\n"
}

func amd64_emit_functions_range(function_ssa_program program, int start, int end) string {
    if start >= end { return "" }
    if end - start == 1 { return amd64_emit_function(program, start) }
    middle := start + (end - start) / 2
    left := amd64_emit_functions_range(program, start, middle)
    right := amd64_emit_functions_range(program, middle, end)
    return left + right
}

func emit_function_ssa_amd64(function_ssa_program program) amd64_program_result {
    error := amd64_validate_program(program)
    if error != "" { return amd64_fail(error) }
    f := 0
    for f < len(program.functions) {
        if ssa_function_external(program.functions[f]) { return amd64_fail("unresolved external function: " + program.functions[f].symbol) }
        f = f + 1
    }
    text := ".text\n" + amd64_emit_functions_range(program, 0, len(program.functions))
    entry_index := ssa_function_index(program.functions, program.entry_symbol)
    text = text + ".globl s_native_entry\n.type s_native_entry, @function\ns_native_entry:\n  jmp " + amd64_function_name(entry_index) + "\n.size s_native_entry, .-s_native_entry\n"
        + ".Ls_native_divzero:\n  movl $86, %edi\n  movl $60, %eax\n  syscall\n  ud2\n"
        + ".section .note.GNU-stack,\"\",@progbits\n"
    if amd64_needs_arena(program) { text = text + amd64_record_allocator() }
    if amd64_needs_intrinsics(program) { text = text + amd64_native_intrinsic_runtime() }
    if len(program.globals) > 0 { text = text + amd64_emit_global_initializers(program) }
    else if amd64_needs_arena(program) { text = text + ".bss\n.globl s_native_gc_roots_begin,s_native_gc_roots_end\ns_native_gc_roots_begin:\ns_native_gc_roots_end:\n" }
    text = text + ".text\n.Ls_native_bounds:\n  movl $87, %edi\n  movl $60, %eax\n  syscall\n  ud2\n"
    return amd64_program_result { assembly: text, error: "" }
}

func amd64_executable_startup(function_ssa_program program) amd64_program_result {
    error := amd64_validate_program(program)
    if error != "" { return amd64_fail(error) }
    entry := program.functions[ssa_function_index(program.functions, program.entry_symbol)]
    if len(entry.result_types) == 1 && entry.result_types[0] != "int" && entry.result_types[0] != "()" { return amd64_fail("amd64 startup: entry result must be int or unit") }
    if len(entry.parameter_types) == 1 && entry.parameter_types[0] != "int" { return amd64_fail("amd64 startup: entry parameter must be int") }
    if len(entry.parameter_types) > 1 { return amd64_fail("amd64 startup: entry must have zero or one int parameter") }
    text := ".text\n.globl _start\n.type _start, @function\n_start:\n"
    if amd64_needs_arena(program) { text = text + "  movq %rsp, s_native_gc_stack_top(%rip)\n" }
    if amd64_needs_intrinsics(program) {
        text = text + "  movq (%rsp), %rax\n  movq %rax, .Ls_native_argc(%rip)\n  leaq 8(%rsp), %rdx\n  movq %rdx, .Ls_native_argv(%rip)\n  leaq 16(%rsp,%rax,8), %rdx\n  movq %rdx, .Ls_native_envp(%rip)\n"
    }
    if len(program.globals) > 0 {
        text = text + "  movq %rsp, %r12\n  andq $-16, %rsp\n  call s_native_initialize_globals\n  movq %r12, %rsp\n"
    }
    if len(entry.parameter_types) == 1 {
        // Accumulate a negative number: the negative range includes INT64_MIN.
        // Compare: before each multiply/subtract, with sign-specific last digit.
        text = text + "  cmpq $2, (%rsp)\n  jne .Ls_native_arg_error\n  movq 16(%rsp), %rsi\n"
            + "  xorl %eax, %eax\n  xorl %r8d, %r8d\n  movzbl (%rsi), %edx\n"
            + "  cmpb $45, %dl\n  jne .Ls_native_arg_plus\n  movl $1, %r8d\n  incq %rsi\n  jmp .Ls_native_arg_digits\n"
            + ".Ls_native_arg_plus:\n  cmpb $43, %dl\n  jne .Ls_native_arg_digits\n  incq %rsi\n"
            + ".Ls_native_arg_digits:\n  cmpb $0, (%rsi)\n  je .Ls_native_arg_error\n  movabsq $-922337203685477580, %r10\n"
            + ".Ls_native_arg_loop:\n  movzbl (%rsi), %edx\n  testb %dl, %dl\n  je .Ls_native_arg_done\n"
            + "  subq $48, %rdx\n  cmpq $9, %rdx\n  ja .Ls_native_arg_error\n"
            + "  cmpq %r10, %rax\n  jl .Ls_native_arg_error\n  jne .Ls_native_arg_accumulate\n"
            + "  movl $7, %r11d\n  addq %r8, %r11\n  cmpq %r11, %rdx\n  ja .Ls_native_arg_error\n"
            + ".Ls_native_arg_accumulate:\n  imulq $10, %rax, %rax\n  subq %rdx, %rax\n  incq %rsi\n  jmp .Ls_native_arg_loop\n"
            + ".Ls_native_arg_done:\n  testl %r8d, %r8d\n  jne .Ls_native_arg_ready\n  negq %rax\n"
            + ".Ls_native_arg_ready:\n  movq %rax, %rdi\n"
    }
    text = text + "  andq $-16, %rsp\n  call s_native_entry\n"
    if len(entry.result_types) == 0 { text = text + "  xorl %edi, %edi\n" } else { text = text + "  movq %rax, %rdi\n" }
    text = text + "  movl $60, %eax\n  syscall\n  ud2\n"
        + ".Ls_native_arg_error:\n  movl $2, %edi\n  movl $60, %eax\n  syscall\n  ud2\n.size _start, .-_start\n"
        + ".section .note.GNU-stack,\"\",@progbits\n"
    return amd64_program_result { assembly: text, error: "" }
}

// The checked-in native runtime is regenerated from src/runtime/native_gc.c.
// Collection is non-moving; frame slots, saved GPRs and globals are roots.
func amd64_record_allocator() string {
    return ".text\n.Ls_native_alloc:\n pushq %rax\n pushq %rbp\n pushq %rbx\n pushq %rcx\n pushq %rdx\n pushq %rsi\n pushq %rdi\n pushq %r8\n pushq %r9\n pushq %r10\n pushq %r11\n pushq %r12\n pushq %r13\n pushq %r14\n pushq %r15\n movq %rsp,%rsi\n movq %rsp,%rbp\n andq $-16,%rsp\n call s_native_gc_alloc\n movq %rbp,%rsp\n popq %r15\n popq %r14\n popq %r13\n popq %r12\n popq %r11\n popq %r10\n popq %r9\n popq %r8\n popq %rdi\n popq %rsi\n popq %rdx\n popq %rcx\n popq %rbx\n popq %rbp\n addq $8,%rsp\n ret\n\t.file\t\"native_gc.c\"\n\t.text\n\t.p2align 4\n\t.type\tadd_slab, @function\nadd_slab:\n.LFB7:\n\t.cfi_startproc\n\tcmpq\t$8192, slab_count(%rip)\n\tje\t.L25\n\tpushq\t%r15\n\t.cfi_def_cfa_offset 16\n\t.cfi_offset 15, -16\n\tmovl\t%edi, %ecx\n\tmovl\t$1048576, %eax\n\tmovl\t$34, %r10d\n\tpushq\t%r14\n\t.cfi_def_cfa_offset 24\n\t.cfi_offset 14, -24\n\tmovq\t$-1, %r8\n\tmovl\t%edi, %r14d\n"
        + "\tmovl\t$3, %edx\n\tpushq\t%r13\n\t.cfi_def_cfa_offset 32\n\t.cfi_offset 13, -32\n\tmovl\t$9, %r13d\n\tpushq\t%r12\n\t.cfi_def_cfa_offset 40\n\t.cfi_offset 12, -40\n\tpushq\t%rbp\n\t.cfi_def_cfa_offset 48\n\t.cfi_offset 6, -48\n\tmovq\t%rdi, %rbp\n\tpushq\t%rbx\n\t.cfi_def_cfa_offset 56\n\t.cfi_offset 3, -56\n\tmovl\t$1, %ebx\n\tsalq\t%cl, %rbx\n\tcmpq\t%rax, %rbx\n\tcmovb\t%rax, %rbx\n\txorl\t%r9d, %r9d\n\txorl\t%edi, %edi\n\tmovq\t%r13, %rax\n\tmovq\t%rbx, %rsi\n#APP\n# 22 \"native_gc.c\" 1\n\tsyscall\n# 0 \"\" 2\n#NO_APP\n\tmovq\t%rax, %r12\n\tleaq\t-1(%rax), %rax\n\tcmpq\t$-4097, %rax\n\tjbe\t.L26\n.L23:\n\txorl\t%eax, %eax\n.L1:\n\tpopq\t%rbx\n\t.cfi_remember_state\n\t.cfi_restore 3\n\t.cfi_def_cfa_offset 48\n\tpopq\t%rbp\n\t.cfi_restore 6\n\t.cfi_def_cfa_offset 40\n\tpopq\t%r12\n\t.cfi_restore 12\n\t.cfi_def_cfa_offset 32\n\tpopq\t%r13\n\t.cfi_restore 13\n"
        + "\t.cfi_def_cfa_offset 24\n\tpopq\t%r14\n\t.cfi_restore 14\n\t.cfi_def_cfa_offset 16\n\tpopq\t%r15\n\t.cfi_restore 15\n\t.cfi_def_cfa_offset 8\n\tret\n\t.p2align 4,,10\n\t.p2align 3\n.L26:\n\t.cfi_restore_state\n\tmovq\t%rbx, %r15\n\tmovl\t%ebp, %ecx\n\tshrq\t%cl, %r15\n\tleaq\t4095(%r15), %rax\n\tandq\t$-4096, %rax\n\tmovq\t%rax, %rsi\n\tmovq\t%r13, %rax\n#APP\n# 22 \"native_gc.c\" 1\n\tsyscall\n# 0 \"\" 2\n#NO_APP\n\tcmpq\t$-4096, %rax\n\tja\t.L5\n\ttestq\t%rax, %rax\n\tje\t.L5\n\tmovq\tslab_count(%rip), %r8\n\tleaq\tslabs(%rip), %r11\n\ttestq\t%r8, %r8\n\tje\t.L7\n\tleaq\t(%r8,%r8,2), %rdx\n\tleaq\tslabs(%rip), %r11\n\tmovq\t%r8, %rcx\n\tsalq\t$4, %rdx\n\tleaq\t-48(%r11,%rdx), %rdx\n\tjmp\t.L8\n\t.p2align 4,,10\n\t.p2align 3\n.L10:\n\tmovdqa\t(%rdx), %xmm0\n\tmovdqa\t16(%rdx), %xmm1\n\tsubq\t$48, %rdx\n\tmovdqa\t80(%rdx), %xmm2\n\tmovaps\t%xmm0, 96(%rdx)\n\tmovaps\t%xmm1, 112(%rdx)\n"
        + "\tmovaps\t%xmm2, 128(%rdx)\n\ttestq\t%rcx, %rcx\n\tje\t.L7\n.L8:\n\tmovq\t%rcx, %rdi\n\tsubq\t$1, %rcx\n\tcmpq\t%r12, (%rdx)\n\tja\t.L10\n.L9:\n\tleaq\t(%rdi,%rdi,2), %rdx\n\taddq\t$1, %r8\n\tsalq\t$4, %rdx\n\tmovq\t%r8, slab_count(%rip)\n\taddq\t%r11, %rdx\n\tmovq\t%r12, (%rdx)\n\tmovq\t%rbx, 8(%rdx)\n\tmovq\t%rbp, 16(%rdx)\n\tmovq\t%r15, 24(%rdx)\n\tmovq\t%rax, 32(%rdx)\n\tmovq\t%rsi, 40(%rdx)\n\ttestq\t%r15, %r15\n\tje\t.L12\n\tleaq\tfree_head(%rip), %rdi\n\txorl\t%edx, %edx\n\tmovq\t(%rdi,%rbp,8), %rax\n\t.p2align 4,,10\n\t.p2align 3\n.L11:\n\tmovq\t%rax, %rsi\n\tmovl\t%r14d, %ecx\n\tmovq\t%rdx, %rax\n\taddq\t$1, %rdx\n\tsalq\t%cl, %rax\n\taddq\t%r12, %rax\n\tmovq\t%rsi, (%rax)\n\tcmpq\t%rdx, %r15\n\tjne\t.L11\n\tmovq\t%rax, (%rdi,%rbp,8)\n\tmovl\t$1, %eax\n\tjmp\t.L1\n\t.p2align 4,,10\n\t.p2align 3\n.L5:\n\txorl\t%r10d, %r10d\n\txorl\t%r8d, %r8d\n\txorl\t%r9d, %r9d\n"
        + "\tmovl\t$11, %eax\n\txorl\t%edx, %edx\n\tmovq\t%r12, %rdi\n\tmovq\t%rbx, %rsi\n#APP\n# 22 \"native_gc.c\" 1\n\tsyscall\n# 0 \"\" 2\n#NO_APP\n\tjmp\t.L23\n\t.p2align 4,,10\n\t.p2align 3\n.L25:\n\t.cfi_def_cfa_offset 8\n\t.cfi_restore 3\n\t.cfi_restore 6\n\t.cfi_restore 12\n\t.cfi_restore 13\n\t.cfi_restore 14\n\t.cfi_restore 15\n\txorl\t%eax, %eax\n\tret\n\t.p2align 4,,10\n\t.p2align 3\n.L7:\n\t.cfi_def_cfa_offset 56\n\t.cfi_offset 3, -56\n\t.cfi_offset 6, -48\n\t.cfi_offset 12, -40\n\t.cfi_offset 13, -32\n\t.cfi_offset 14, -24\n\t.cfi_offset 15, -16\n\txorl\t%edi, %edi\n\tjmp\t.L9\n.L12:\n\tmovl\t$1, %eax\n\tjmp\t.L1\n\t.cfi_endproc\n.LFE7:\n\t.size\tadd_slab, .-add_slab\n\t.p2align 4\n\t.type\tdie, @function\ndie:\n.LFB1:\n\t.cfi_startproc\n\txorl\t%edx, %edx\n\txorl\t%r10d, %r10d\n\txorl\t%r8d, %r8d\n\txorl\t%r9d, %r9d\n\tmovl\t$60, %eax\n\tmovl\t$126, %edi\n\tmovq\t%rdx, %rsi\n"
        + "#APP\n# 22 \"native_gc.c\" 1\n\tsyscall\n# 0 \"\" 2\n#NO_APP\n\t.cfi_endproc\n.LFE1:\n\t.size\tdie, .-die\n\t.p2align 4\n\t.type\tmark, @function\nmark:\n.LFB4:\n\t.cfi_startproc\n\tmovq\tslab_count(%rip), %rcx\n\ttestq\t%rcx, %rcx\n\tje\t.L56\n\tcmpq\t%rdi, slabs(%rip)\n\tpushq\t%r15\n\t.cfi_def_cfa_offset 16\n\t.cfi_offset 15, -16\n\tpushq\t%r14\n\t.cfi_def_cfa_offset 24\n\t.cfi_offset 14, -24\n\tpushq\t%r13\n\t.cfi_def_cfa_offset 32\n\t.cfi_offset 13, -32\n\tpushq\t%r12\n\t.cfi_def_cfa_offset 40\n\t.cfi_offset 12, -40\n\tleaq\tslabs(%rip), %r12\n\tpushq\t%rbp\n\t.cfi_def_cfa_offset 48\n\t.cfi_offset 6, -48\n\tmovq\t%rdi, %rbp\n\tpushq\t%rbx\n\t.cfi_def_cfa_offset 56\n\t.cfi_offset 3, -56\n\tja\t.L28\n\tleaq\t-3(%rcx,%rcx,2), %rax\n\txorl\t%ebx, %ebx\n\tsalq\t$4, %rax\n\taddq\t%r12, %rax\n\tmovq\t8(%rax), %rdx\n\taddq\t(%rax), %rdx\n\tcmpq\t%rdi, %rdx\n\tja\t.L31\n\tjmp\t.L28\n"
        + "\t.p2align 4,,10\n\t.p2align 3\n.L32:\n\tmovq\t%rcx, %rax\n\tsubq\t%rbx, %rax\n\tshrq\t%rax\n\taddq\t%rbx, %rax\n\tleaq\t(%rax,%rax,2), %rdx\n\tsalq\t$4, %rdx\n\tcmpq\t%rbp, (%r12,%rdx)\n\tjbe\t.L59\n\tmovq\t%rax, %rcx\n.L31:\n\tcmpq\t%rcx, %rbx\n\tjb\t.L32\n\ttestq\t%rbx, %rbx\n\tje\t.L28\n\tsubq\t$1, %rbx\n\tleaq\t(%rbx,%rbx,2), %rax\n\tsalq\t$4, %rax\n\taddq\t%r12, %rax\n\tsubq\t(%rax), %rbp\n\tcmpq\t8(%rax), %rbp\n\tjnb\t.L28\n\tmovq\t16(%rax), %rcx\n\tmovq\t32(%rax), %rsi\n\tshrq\t%cl, %rbp\n\taddq\t%rbp, %rsi\n\tcmpb\t$1, (%rsi)\n\tjne\t.L28\n\tmovq\tqueue_count(%rip), %rdx\n\tcmpq\tqueue_capacity(%rip), %rdx\n\tmovb\t$2, (%rsi)\n\tmovq\tqueue(%rip), %r14\n\tje\t.L60\n.L34:\n\tleaq\t(%rbx,%rbx,2), %rax\n\tsalq\t$4, %rax\n\taddq\t%rax, %r12\n\tleaq\t1(%rdx), %rax\n\tmovq\t16(%r12), %rcx\n\tmovq\t%rax, queue_count(%rip)\n\tsalq\t%cl, %rbp\n\taddq\t(%r12), %rbp\n"
        + "\tmovq\t%rbp, (%r14,%rdx,8)\n.L28:\n\tpopq\t%rbx\n\t.cfi_restore 3\n\t.cfi_def_cfa_offset 48\n\tpopq\t%rbp\n\t.cfi_restore 6\n\t.cfi_def_cfa_offset 40\n\tpopq\t%r12\n\t.cfi_restore 12\n\t.cfi_def_cfa_offset 32\n\tpopq\t%r13\n\t.cfi_restore 13\n\t.cfi_def_cfa_offset 24\n\tpopq\t%r14\n\t.cfi_restore 14\n\t.cfi_def_cfa_offset 16\n\tpopq\t%r15\n\t.cfi_restore 15\n\t.cfi_def_cfa_offset 8\n\tret\n\t.p2align 4,,10\n\t.p2align 3\n.L56:\n\tret\n\t.p2align 4,,10\n\t.p2align 3\n.L59:\n\t.cfi_def_cfa_offset 56\n\t.cfi_offset 3, -56\n\t.cfi_offset 6, -48\n\t.cfi_offset 12, -40\n\t.cfi_offset 13, -32\n\t.cfi_offset 14, -24\n\t.cfi_offset 15, -16\n\tleaq\t1(%rax), %rbx\n\tjmp\t.L31\n.L60:\n\ttestq\t%rdx, %rdx\n\tje\t.L43\n\tleaq\t(%rdx,%rdx), %r15\n\tmovq\t%r15, %rax\n\tshrq\t$61, %rax\n\tjne\t.L36\n\tcmpq\t%r15, %rdx\n\tja\t.L36\n\tmovq\t%rdx, %rsi\n\tsalq\t$4, %rsi\n.L35:\n\tmovl\t$34, %r10d\n"
        + "\txorl\t%r9d, %r9d\n\tmovl\t$9, %eax\n\txorl\t%edi, %edi\n\tmovq\t$-1, %r8\n\tmovl\t$3, %edx\n#APP\n# 22 \"native_gc.c\" 1\n\tsyscall\n# 0 \"\" 2\n#NO_APP\n\tmovq\t%rax, %r13\n\tcmpq\t$-4096, %rax\n\tja\t.L36\n\tmovq\t%rax, %r14\n\ttestq\t%rax, %rax\n\tje\t.L36\n\tmovq\tqueue(%rip), %rdi\n\tmovq\tqueue_count(%rip), %rdx\n\tmovq\t%rdi, %rsi\n\tleaq\t(%rax,%rdx,8), %r8\n\tsubq\t%rax, %rsi\n\ttestq\t%rdx, %rdx\n\tje\t.L41\n\t.p2align 4,,10\n\t.p2align 3\n.L40:\n\tmovq\t(%rsi,%rax), %rcx\n\taddq\t$8, %rax\n\tmovq\t%rcx, -8(%rax)\n\tcmpq\t%rax, %r8\n\tjne\t.L40\n.L41:\n\ttestq\t%rdi, %rdi\n\tje\t.L39\n\tmovq\tqueue_capacity(%rip), %rax\n\txorl\t%r10d, %r10d\n\txorl\t%r8d, %r8d\n\txorl\t%r9d, %r9d\n\txorl\t%edx, %edx\n\tleaq\t0(,%rax,8), %rsi\n\tmovl\t$11, %eax\n#APP\n# 22 \"native_gc.c\" 1\n\tsyscall\n# 0 \"\" 2\n#NO_APP\n\tmovq\tqueue_count(%rip), %rdx\n.L39:\n\tmovq\t%r13, queue(%rip)\n"
        + "\tmovq\t%r15, queue_capacity(%rip)\n\tjmp\t.L34\n.L36:\n\tcall\tdie\n.L43:\n\tmovl\t$32768, %esi\n\tmovl\t$4096, %r15d\n\tjmp\t.L35\n\t.cfi_endproc\n.LFE4:\n\t.size\tmark, .-mark\n\t.p2align 4\n\t.type\tcollect.part.0, @function\ncollect.part.0:\n.LFB9:\n\t.cfi_startproc\n\tpushq\t%r15\n\t.cfi_def_cfa_offset 16\n\t.cfi_offset 15, -16\n\tpushq\t%r14\n\t.cfi_def_cfa_offset 24\n\t.cfi_offset 14, -24\n\tpushq\t%r13\n\t.cfi_def_cfa_offset 32\n\t.cfi_offset 13, -32\n\tpushq\t%r12\n\t.cfi_def_cfa_offset 40\n\t.cfi_offset 12, -40\n\tpushq\t%rbp\n\t.cfi_def_cfa_offset 48\n\t.cfi_offset 6, -48\n\tleaq\ts_native_gc_roots_end(%rip), %rbp\n\tpushq\t%rbx\n\t.cfi_def_cfa_offset 56\n\t.cfi_offset 3, -56\n\tleaq\ts_native_gc_roots_begin(%rip), %rbx\n\tsubq\t$24, %rsp\n\t.cfi_def_cfa_offset 80\n\tcmpq\t%rbx, %rbp\n\tjbe\t.L65\n\t.p2align 4,,10\n\t.p2align 3\n.L62:\n\tmovq\t(%rbx), %rdi\n"
        + "\taddq\t$8, %rbx\n\tcall\tmark\n\tcmpq\t%rbx, %rbp\n\tja\t.L62\n.L65:\n\txorl\t%ebp, %ebp\n\tmovq\tslab_count(%rip), %r14\n\tleaq\tslabs(%rip), %rbx\n\tcmpq\t$0, queue_count(%rip)\n\tje\t.L64\n\t.p2align 4,,10\n\t.p2align 3\n.L63:\n\tmovq\tqueue(%rip), %rax\n\tmovq\t%r14, %rsi\n\txorl\t%ecx, %ecx\n\tmovq\t(%rax,%rbp,8), %r12\n\tjmp\t.L68\n\t.p2align 4,,10\n\t.p2align 3\n.L69:\n\tmovq\t%rsi, %rax\n\tsubq\t%rcx, %rax\n\tshrq\t%rax\n\taddq\t%rcx, %rax\n\tleaq\t(%rax,%rax,2), %rdx\n\tsalq\t$4, %rdx\n\tcmpq\t(%rbx,%rdx), %r12\n\tjnb\t.L103\n\tmovq\t%rax, %rsi\n.L68:\n\tcmpq\t%rcx, %rsi\n\tja\t.L69\n\tleaq\t-3(%rcx,%rcx,2), %rax\n\tmovl\t$1, %r13d\n\tsalq\t$4, %rax\n\tmovq\t16(%rbx,%rax), %rcx\n\tsalq\t%cl, %r13\n\taddq\t%r12, %r13\n\tcmpq\t%r13, %r12\n\tjnb\t.L71\n\t.p2align 4,,10\n\t.p2align 3\n.L70:\n\tmovq\t(%r12), %rdi\n\taddq\t$8, %r12\n\tcall\tmark\n\tcmpq\t%r12, %r13\n\tja\t.L70\n"
        + ".L71:\n\taddq\t$1, %rbp\n\tcmpq\tqueue_count(%rip), %rbp\n\tjb\t.L63\n.L64:\n\tleaq\tfree_head(%rip), %r13\n\tmovq\t%r13, %rax\n\tleaq\t472(%r13), %rdx\n\t.p2align 4,,10\n\t.p2align 3\n.L66:\n\tmovq\t$0, (%rax)\n\taddq\t$8, %rax\n\tcmpq\t%rdx, %rax\n\tjne\t.L66\n\ttestq\t%r14, %r14\n\tje\t.L83\n\tleaq\tslabs(%rip), %rbx\n\tmovq\t$0, (%rsp)\n\txorl\t%r14d, %r14d\n\txorl\t%r15d, %r15d\n\tmovq\t%rbx, 16(%rsp)\n\tmovq\t%rbx, %r12\n\t.p2align 4,,10\n\t.p2align 3\n.L80:\n\tmovq\t24(%r12), %r9\n\tmovq\t(%r12), %rdi\n\tmovq\t8(%r12), %rsi\n\tmovq\t16(%r12), %r8\n\tmovq\t32(%r12), %rbx\n\tmovq\t40(%r12), %rbp\n\ttestq\t%r9, %r9\n\tje\t.L73\n\tmovq\t%rbx, %rax\n\tleaq\t(%r9,%rbx), %r10\n\txorl\t%edx, %edx\n\t.p2align 4,,10\n\t.p2align 3\n.L75:\n\txorl\t%ecx, %ecx\n\tcmpb\t$2, (%rax)\n\tsete\t%cl\n\taddq\t$1, %rax\n\taddq\t%rcx, %rdx\n\tcmpq\t%rax, %r10\n\tjne\t.L75\n\ttestq\t%rdx, %rdx\n"
        + "\tje\t.L73\n\tmovl\t%r8d, %ecx\n\tmovl\t$1, %r11d\n\tmovq\t%rsi, 8(%rsp)\n\txorl\t%eax, %eax\n\tsalq\t%cl, %r11\n\tmovq\t(%rsp), %r10\n\tmovl\t%r8d, %ecx\n\tjmp\t.L76\n\t.p2align 4,,10\n\t.p2align 3\n.L78:\n\tmovq\t%rax, %rdx\n\tmovb\t$0, (%rbx,%rax)\n\tmovq\t0(%r13,%r8,8), %rsi\n\taddq\t$1, %rax\n\tsalq\t%cl, %rdx\n\taddq\t%rdi, %rdx\n\tmovq\t%rsi, (%rdx)\n\tmovq\t%rdx, 0(%r13,%r8,8)\n\tcmpq\t%rax, %r9\n\tje\t.L104\n.L76:\n\tcmpb\t$2, (%rbx,%rax)\n\tjne\t.L78\n\tmovb\t$1, (%rbx,%rax)\n\taddq\t$1, %rax\n\taddq\t%r11, %r10\n\tcmpq\t%rax, %r9\n\tjne\t.L76\n.L104:\n\tleaq\t(%r14,%r14,2), %rax\n\tmovq\t8(%rsp), %rsi\n\tmovq\t%r10, (%rsp)\n\taddq\t$1, %r14\n\tsalq\t$4, %rax\n\taddq\t16(%rsp), %rax\n\tmovq\t%rdi, (%rax)\n\tmovq\t%rsi, 8(%rax)\n\tmovq\t%r8, 16(%rax)\n\tmovq\t%r9, 24(%rax)\n\tmovq\t%rbx, 32(%rax)\n\tmovq\t%rbp, 40(%rax)\n\tjmp\t.L77\n\t.p2align 4,,10\n\t.p2align 3\n.L103:\n"
        + "\tleaq\t1(%rax), %rcx\n\tjmp\t.L68\n\t.p2align 4,,10\n\t.p2align 3\n.L73:\n\txorl\t%r10d, %r10d\n\txorl\t%r8d, %r8d\n\txorl\t%r9d, %r9d\n\txorl\t%edx, %edx\n\tmovl\t$11, %eax\n#APP\n# 22 \"native_gc.c\" 1\n\tsyscall\n# 0 \"\" 2\n#NO_APP\n\tmovl\t$11, %eax\n\tmovq\t%rbx, %rdi\n\tmovq\t%rbp, %rsi\n#APP\n# 22 \"native_gc.c\" 1\n\tsyscall\n# 0 \"\" 2\n#NO_APP\n.L77:\n\taddq\t$1, %r15\n\taddq\t$48, %r12\n\tcmpq\tslab_count(%rip), %r15\n\tjb\t.L80\n\tmovq\t(%rsp), %rdi\n\tmovl\t$33554432, %eax\n\tcmpq\t%rax, %rdi\n\tcmovnb\t%rdi, %rax\n.L72:\n\tmovq\t%r14, slab_count(%rip)\n\tmovq\t$0, allocated_since_gc(%rip)\n\tmovq\t%rax, period(%rip)\n\taddq\t$24, %rsp\n\t.cfi_remember_state\n\t.cfi_def_cfa_offset 56\n\tpopq\t%rbx\n\t.cfi_restore 3\n\t.cfi_def_cfa_offset 48\n\tpopq\t%rbp\n\t.cfi_restore 6\n\t.cfi_def_cfa_offset 40\n\tpopq\t%r12\n\t.cfi_restore 12\n\t.cfi_def_cfa_offset 32\n\tpopq\t%r13\n"
        + "\t.cfi_restore 13\n\t.cfi_def_cfa_offset 24\n\tpopq\t%r14\n\t.cfi_restore 14\n\t.cfi_def_cfa_offset 16\n\tpopq\t%r15\n\t.cfi_restore 15\n\t.cfi_def_cfa_offset 8\n\tret\n.L83:\n\t.cfi_restore_state\n\tmovl\t$33554432, %eax\n\tjmp\t.L72\n\t.cfi_endproc\n.LFE9:\n\t.size\tcollect.part.0, .-collect.part.0\n\t.p2align 4\n\t.globl\ts_native_gc_alloc\n\t.type\ts_native_gc_alloc, @function\ns_native_gc_alloc:\n.LFB8:\n\t.cfi_startproc\n\tendbr64\n\tpushq\t%r14\n\t.cfi_def_cfa_offset 16\n\t.cfi_offset 14, -16\n\tmovl\t$4, %ecx\n\tmovl\t$1, %eax\n\tpushq\t%r13\n\t.cfi_def_cfa_offset 24\n\t.cfi_offset 13, -24\n\tpushq\t%r12\n\t.cfi_def_cfa_offset 32\n\t.cfi_offset 12, -32\n\tmovq\t%rsi, %r12\n\tpushq\t%rbp\n\t.cfi_def_cfa_offset 40\n\t.cfi_offset 6, -40\n\tpushq\t%rbx\n\t.cfi_def_cfa_offset 48\n\t.cfi_offset 3, -48\n\tsubq\t$16, %rsp\n\t.cfi_def_cfa_offset 64\n\tjmp\t.L106\n\t.p2align 4,,10\n"
        + "\t.p2align 3\n.L107:\n\taddq\t$1, %rcx\n\tcmpq\t$59, %rcx\n\tje\t.L118\n.L106:\n\tmovq\t%rax, %rbx\n\tmovl\t%ecx, %ebp\n\tsalq\t%cl, %rbx\n\tcmpq\t%rdi, %rbx\n\tjb\t.L107\n\tmovq\tperiod(%rip), %rax\n\tcmpq\t%rax, allocated_since_gc(%rip)\n\tjnb\t.L136\n.L108:\n\tleaq\tfree_head(%rip), %r13\n\tmovq\t0(%r13,%rcx,8), %r8\n\ttestq\t%r8, %r8\n\tje\t.L137\n.L112:\n\tmovq\t(%r8), %rax\n\tmovq\tslab_count(%rip), %rsi\n\tleaq\tslabs(%rip), %rdi\n\tmovq\t%rax, 0(%r13,%rcx,8)\n\txorl\t%ecx, %ecx\n\tjmp\t.L120\n\t.p2align 4,,10\n\t.p2align 3\n.L121:\n\tmovq\t%rsi, %rax\n\tsubq\t%rcx, %rax\n\tshrq\t%rax\n\taddq\t%rcx, %rax\n\tleaq\t(%rax,%rax,2), %rdx\n\tsalq\t$4, %rdx\n\tcmpq\t%r8, (%rdi,%rdx)\n\tjbe\t.L138\n\tmovq\t%rax, %rsi\n.L120:\n\tcmpq\t%rsi, %rcx\n\tjb\t.L121\n\tleaq\t-3(%rcx,%rcx,2), %rax\n\tmovl\t%ebp, %ecx\n\tsalq\t$4, %rax\n\taddq\t%rax, %rdi\n\tmovq\t%r8, %rax\n"
        + "\tmovq\t32(%rdi), %rdx\n\tsubq\t(%rdi), %rax\n\tshrq\t%cl, %rax\n\tmovb\t$1, (%rdx,%rax)\n\txorl\t%eax, %eax\n\t.p2align 4,,10\n\t.p2align 3\n.L122:\n\tmovq\t$0, (%rax,%r8)\n\taddq\t$8, %rax\n\tcmpq\t%rax, %rbx\n\tja\t.L122\n\taddq\t%rbx, allocated_since_gc(%rip)\n\taddq\t$16, %rsp\n\t.cfi_remember_state\n\t.cfi_def_cfa_offset 48\n\tmovq\t%r8, %rax\n\tpopq\t%rbx\n\t.cfi_restore 3\n\t.cfi_def_cfa_offset 40\n\tpopq\t%rbp\n\t.cfi_restore 6\n\t.cfi_def_cfa_offset 32\n\tpopq\t%r12\n\t.cfi_restore 12\n\t.cfi_def_cfa_offset 24\n\tpopq\t%r13\n\t.cfi_restore 13\n\t.cfi_def_cfa_offset 16\n\tpopq\t%r14\n\t.cfi_restore 14\n\t.cfi_def_cfa_offset 8\n\tret\n\t.p2align 4,,10\n\t.p2align 3\n.L138:\n\t.cfi_restore_state\n\tleaq\t1(%rax), %rcx\n\tjmp\t.L120\n\t.p2align 4,,10\n\t.p2align 3\n.L136:\n\tmovq\ts_native_gc_stack_top(%rip), %r14\n\ttestq\t%r14, %r14\n\tje\t.L139\n\tmovq\t$0, queue_count(%rip)\n"
        + "\tmovq\t%r12, %r13\n\tcmpq\t%r14, %r12\n\tjnb\t.L111\n\t.p2align 4,,10\n\t.p2align 3\n.L110:\n\tmovq\t0(%r13), %rdi\n\taddq\t$8, %r13\n\tmovq\t%rcx, 8(%rsp)\n\tcall\tmark\n\tcmpq\t%r13, %r14\n\tmovq\t8(%rsp), %rcx\n\tja\t.L110\n.L111:\n\tmovq\t%rcx, 8(%rsp)\n\tcall\tcollect.part.0\n\tmovq\t8(%rsp), %rcx\n\tjmp\t.L108\n\t.p2align 4,,10\n\t.p2align 3\n.L137:\n\tmovq\t%rcx, %rdi\n\tmovq\t%rcx, 8(%rsp)\n\tcall\tadd_slab\n\tmovq\t8(%rsp), %rcx\n\ttestl\t%eax, %eax\n\tje\t.L113\n.L135:\n\tmovq\t0(%r13,%rcx,8), %r8\n\tjmp\t.L112\n\t.p2align 4,,10\n\t.p2align 3\n.L118:\n\tcall\tdie\n.L139:\n\tmovq\t$0, allocated_since_gc(%rip)\n\tmovq\t$-1, period(%rip)\n\tjmp\t.L108\n.L113:\n\tmovq\ts_native_gc_stack_top(%rip), %r14\n\ttestq\t%r14, %r14\n\tje\t.L140\n\tmovq\t$0, queue_count(%rip)\n\tcmpq\t%r14, %r12\n\tjnb\t.L117\n\t.p2align 4,,10\n\t.p2align 3\n.L116:\n\tmovq\t(%r12), %rdi\n"
        + "\taddq\t$8, %r12\n\tmovq\t%rcx, 8(%rsp)\n\tcall\tmark\n\tcmpq\t%r12, %r14\n\tmovq\t8(%rsp), %rcx\n\tja\t.L116\n.L117:\n\tmovq\t%rcx, 8(%rsp)\n\tcall\tcollect.part.0\n\tmovq\t8(%rsp), %rcx\n.L115:\n\tmovq\t0(%r13,%rcx,8), %r8\n\ttestq\t%r8, %r8\n\tjne\t.L112\n\tmovq\t%rcx, %rdi\n\tmovq\t%rcx, 8(%rsp)\n\tcall\tadd_slab\n\ttestl\t%eax, %eax\n\tje\t.L118\n\tmovq\t8(%rsp), %rcx\n\tjmp\t.L135\n.L140:\n\tmovq\t$0, allocated_since_gc(%rip)\n\tmovq\t$-1, period(%rip)\n\tjmp\t.L115\n\t.cfi_endproc\n.LFE8:\n\t.size\ts_native_gc_alloc, .-s_native_gc_alloc\n\t.globl\ts_native_gc_stack_top\n\t.bss\n\t.align 8\n\t.type\ts_native_gc_stack_top, @object\n\t.size\ts_native_gc_stack_top, 8\ns_native_gc_stack_top:\n\t.zero\t8\n\t.local\tqueue_capacity\n\t.comm\tqueue_capacity,8,8\n\t.local\tqueue_count\n\t.comm\tqueue_count,8,8\n\t.local\tqueue\n\t.comm\tqueue,8,8\n\t.data\n\t.align 8\n"
        + "\t.type\tperiod, @object\n\t.size\tperiod, 8\nperiod:\n\t.quad\t33554432\n\t.local\tallocated_since_gc\n\t.comm\tallocated_since_gc,8,8\n\t.local\tfree_head\n\t.comm\tfree_head,472,32\n\t.local\tslab_count\n\t.comm\tslab_count,8,8\n\t.local\tslabs\n\t.comm\tslabs,393216,32\n\t.ident\t\"GCC: (Ubuntu 11.4.0-1ubuntu1~22.04.3) 11.4.0\"\n\t.section\t.note.GNU-stack,\"\",@progbits\n\t.section\t.note.gnu.property,\"a\"\n\t.align 8\n\t.long\t1f - 0f\n\t.long\t4f - 1f\n\t.long\t5\n0:\n\t.string\t\"GNU\"\n1:\n\t.align 8\n\t.long\t0xc0000002\n\t.long\t3f - 2f\n2:\n\t.long\t0x3\n3:\n\t.align 8\n4:\n"
}

func amd64_needs_arena(function_ssa_program program) bool {
    f := 0
    for f < len(program.functions) {
        b := 0
        for b < len(program.functions[f].blocks) {
            v := 0
            for v < len(program.functions[f].blocks[b].values) {
                op := program.functions[f].blocks[b].values[v].op
                if op == "reference_new" || op == "native_intrinsic" || op == "string_slice" || op == "string_char_at" || op == "string_concat" || op == "record_new" || op == "record_set" || op == "array_new" || op == "array_append" || op == "array_set" { return true }
                v = v + 1
            }
            b = b + 1
        }
        f = f + 1
    }
    return false
}

func amd64_emit_array(function_ssa_program program, int function_index, int position) string {
    return amd64_emit_array_with_values(program, function_index, position, amd64_function_values(program.functions[function_index]))
}

func amd64_emit_array_with_values(function_ssa_program program, int function_index, int position, function_ssa_value[] values) string {
    value := values[position]
    slot := amd64_slot(values, value.id)
    label := ".Ls_array_" + amd64_integer(function_index) + "_" + amd64_integer(position)
    if value.op == "array_new" {
        text := "  movq $" + amd64_integer((len(value.operands) + 1) * 8) + ", %rdi\n  call .Ls_native_alloc\n  movq %rax, " + slot + "\n  movq $" + amd64_integer(len(value.operands)) + ", (%rax)\n"
        i := 0
        for i < len(value.operands) {
            text = text + "  movq " + amd64_slot(values, value.operands[i]) + ", %r10\n  movq %r10, " + amd64_integer((i + 1) * 8) + "(%rax)\n"
            i = i + 1
        }
        return text
    }
    target := amd64_slot(values, value.operands[0])
    text := "  movq " + target + ", %rax\n"
    if value.op == "array_len" { return text + "  testq %rax, %rax\n  je " + label + "_done\n  movq (%rax), %rax\n" + label + "_done:\n  movq %rax, " + slot + "\n" }
    if value.op == "array_get" {
        return text + "  testq %rax, %rax\n  je .Ls_native_bounds\n  movq " + amd64_slot(values, value.operands[1]) + ", %r10\n  cmpq (%rax), %r10\n  jae .Ls_native_bounds\n  movq 8(%rax,%r10,8), %rax\n  movq %rax, " + slot + "\n"
    }
    if value.op == "array_set" {
        return text + "  testq %rax, %rax\n  je .Ls_native_bounds\n  movq " + amd64_slot(values, value.operands[1]) + ", %r10\n  cmpq (%rax), %r10\n  jae .Ls_native_bounds\n"
            + "  movq (%rax), %rdi\n  incq %rdi\n  shlq $3, %rdi\n  call .Ls_native_alloc\n  movq %rax, " + slot + "\n"
            + "  movq " + target + ", %r8\n  movq (%r8), %rsi\n  movq %rsi, (%rax)\n  xorl %ecx, %ecx\n"
            + label + "_copy:\n  cmpq %rsi, %rcx\n  jae " + label + "_copied\n  movq 8(%r8,%rcx,8), %r10\n  movq %r10, 8(%rax,%rcx,8)\n  incq %rcx\n  jmp " + label + "_copy\n"
            + label + "_copied:\n  movq " + amd64_slot(values, value.operands[1]) + ", %r10\n  movq " + amd64_slot(values, value.operands[2]) + ", %r11\n  movq %r11, 8(%rax,%r10,8)\n"
    }
    text = text + "  xorl %edi, %edi\n  testq %rax, %rax\n  je " + label + "_size\n  movq (%rax), %rdi\n" + label + "_size:\n  addq $2, %rdi\n  shlq $3, %rdi\n  call .Ls_native_alloc\n  movq %rax, " + slot + "\n"
        + "  movq " + target + ", %r8\n  xorl %ecx, %ecx\n  xorl %esi, %esi\n  testq %r8, %r8\n  je " + label + "_copied\n  movq (%r8), %rsi\n"
        + label + "_copy:\n  cmpq %rsi, %rcx\n  jae " + label + "_copied\n  movq 8(%r8,%rcx,8), %r10\n  movq %r10, 8(%rax,%rcx,8)\n  incq %rcx\n  jmp " + label + "_copy\n"
        + label + "_copied:\n  movq " + amd64_slot(values, value.operands[1]) + ", %r10\n  movq %r10, 8(%rax,%rsi,8)\n  incq %rsi\n  movq %rsi, (%rax)\n"
    return text
}

// Native strings are immutable: an untagged pointer to byte length then bytes.
// Null is the default empty string. Literal bytes use numeric directives only.
func amd64_emit_string_bytes(string value, int start, int end) string {
    if start >= end { return "" }
    if end - start == 1 { return ".byte " + amd64_integer(__host_byte_at(value, start)) + "\n" }
    middle := start + (end - start) / 2
    left := amd64_emit_string_bytes(value, start, middle)
    right := amd64_emit_string_bytes(value, middle, end)
    return left + right
}

func amd64_emit_string(function_ssa_value[] values, function_ssa_value value, int function_index, int position) string {
    slot := amd64_slot(values, value.id)
    label := ".Ls_string_" + amd64_integer(function_index) + "_" + amd64_integer(position)
    if value.op == "const_string" {
        text := ".pushsection .rodata\n.balign 8\n" + label + ":\n.quad " + amd64_integer(len(value.symbol)) + "\n"
        text = text + amd64_emit_string_bytes(value.symbol, 0, len(value.symbol))
        return text + ".popsection\n  leaq " + label + "(%rip), %rax\n  movq %rax, " + slot + "\n"
    }
    if value.op == "string_len" {
        return "  movq " + amd64_slot(values, value.operands[0]) + ", %rax\n  testq %rax, %rax\n  je " + label + "_done\n  movq (%rax), %rax\n" + label + "_done:\n  movq %rax, " + slot + "\n"
    }
    if value.op != "string_concat" { return amd64_emit_string_compare(values, value, label) }
    return "  pushq %r12\n  pushq %r13\n  pushq %r14\n  pushq %r15\n"
        + "  movq " + amd64_slot(values, value.operands[0]) + ", %r12\n  movq " + amd64_slot(values, value.operands[1]) + ", %r13\n"
        + "  xorl %r14d, %r14d\n  xorl %r15d, %r15d\n  testq %r12, %r12\n  je " + label + "_left\n  movq (%r12), %r14\n"
        + label + "_left:\n  testq %r13, %r13\n  je " + label + "_right\n  movq (%r13), %r15\n"
        + label + "_right:\n  movq %r14, %rdi\n  addq %r15, %rdi\n  jc .Ls_native_bounds\n  movabsq $9223372036854710256, %r10\n  cmpq %r10, %rdi\n  ja .Ls_native_bounds\n  addq $15, %rdi\n  jc .Ls_native_bounds\n  subq $7, %rdi\n  call .Ls_native_alloc\n"
        + "  movq %r14, %rdx\n  addq %r15, %rdx\n  movq %rdx, (%rax)\n  leaq 8(%rax), %rdi\n  leaq 8(%r12), %rsi\n  movq %r14, %rcx\n  cld\n  rep movsb\n"
        + "  leaq 8(%r13), %rsi\n  movq %r15, %rcx\n  rep movsb\n  popq %r15\n  popq %r14\n  popq %r13\n  popq %r12\n  movq %rax, " + slot + "\n"
}

// Compare unsigned bytes, then lengths; never compare allocation addresses.
func amd64_emit_string_compare(function_ssa_value[] values, function_ssa_value value, string label) string {
    instruction := "sete"
    if value.op == "string_ne" { instruction = "setne" }
    if value.op == "string_lt" { instruction = "setl" }
    if value.op == "string_le" { instruction = "setle" }
    if value.op == "string_gt" { instruction = "setg" }
    if value.op == "string_ge" { instruction = "setge" }
    return "  movq " + amd64_slot(values, value.operands[0]) + ", %r8\n  movq " + amd64_slot(values, value.operands[1]) + ", %r9\n"
        + "  xorl %esi, %esi\n  xorl %edi, %edi\n  testq %r8, %r8\n  je " + label + "_left\n  movq (%r8), %rsi\n"
        + label + "_left:\n  testq %r9, %r9\n  je " + label + "_loop_init\n  movq (%r9), %rdi\n"
        + label + "_loop_init:\n  xorl %ecx, %ecx\n" + label + "_loop:\n  cmpq %rsi, %rcx\n  jae " + label + "_length\n  cmpq %rdi, %rcx\n  jae " + label + "_length\n"
        + "  movzbl 8(%r8,%rcx), %eax\n  movzbl 8(%r9,%rcx), %edx\n  subl %edx, %eax\n  jne " + label + "_result\n  incq %rcx\n  jmp " + label + "_loop\n"
        + label + "_length:\n  xorl %eax, %eax\n  cmpq %rdi, %rsi\n  sete %al\n  je " + label + "_equal\n  movl $1, %eax\n  ja " + label + "_result\n  movl $-1, %eax\n  jmp " + label + "_result\n"
        + label + "_equal:\n  xorl %eax, %eax\n" + label + "_result:\n  cmpl $0, %eax\n  " + instruction + " %al\n  movzbq %al, %rax\n  movq %rax, " + amd64_slot(values, value.id) + "\n"
}

func amd64_emit_string_access(function_ssa_value[] values, function_ssa_value value, int function_index, int position) string {
    slot := amd64_slot(values, value.id)
    label := ".Ls_string_access_" + amd64_integer(function_index) + "_" + amd64_integer(position)
    text := "  movq " + amd64_slot(values, value.operands[0]) + ", %r8\n  xorl %edx, %edx\n  testq %r8, %r8\n  je " + label + "_length\n  movq (%r8), %rdx\n" + label + "_length:\n  movq " + amd64_slot(values, value.operands[1]) + ", %r9\n"
    failure := label + "_fail:\n  movq $0, " + slot + "\n" + label + "_done:\n"
    if value.op == "string_byte_at" {
        return text + "  cmpq %rdx, %r9\n  jae " + label + "_fail\n  movzbl 8(%r8,%r9), %eax\n  movq %rax, " + slot + "\n  jmp " + label + "_done\n" + failure
    }
    if value.op == "string_char_at" {
        text = text + "  cmpq %rdx, %r9\n  jae " + label + "_fail\n  movq %r9, %r10\n  incq %r10\n"
    } else {
        text = text + "  movq " + amd64_slot(values, value.operands[2]) + ", %r10\n  cmpq %rdx, %r10\n  ja " + label + "_fail\n  cmpq %r10, %r9\n  ja " + label + "_fail\n"
    }
    return text + "  pushq %r12\n  pushq %r13\n  leaq 8(%r8,%r9), %r12\n  movq %r10, %r13\n  subq %r9, %r13\n  movq %r13, %rdi\n  movabsq $9223372036854710256, %r10\n  cmpq %r10, %rdi\n  ja .Ls_native_bounds\n  addq $8, %rdi\n  call .Ls_native_alloc\n  movq %r13, (%rax)\n  leaq 8(%rax), %rdi\n  movq %r12, %rsi\n  movq %r13, %rcx\n  cld\n  rep movsb\n  popq %r13\n  popq %r12\n  movq %rax, " + slot + "\n  jmp " + label + "_done\n" + failure
}

func amd64_needs_intrinsics(function_ssa_program program) bool {
    f := 0
    for f < len(program.functions) {
        b := 0
        for b < len(program.functions[f].blocks) {
            v := 0
            for v < len(program.functions[f].blocks[b].values) {
                if program.functions[f].blocks[b].values[v].op == "native_intrinsic" { return true }
                v = v + 1
            }
            b = b + 1
        }
        f = f + 1
    }
    return false
}
func amd64_emit_native_intrinsic(function_ssa_value[] values, function_ssa_value value, int function_index, int position) string {
    name := value.symbol
    host_slice_name := "__host" + "_slice"
    string_slice_name := "__string" + "_slice"
    host_byte_at_name := "__host" + "_byte" + "_at"
    host_char_at_name := "__host" + "_char" + "_at"
    string_char_at_name := "__string" + "_char" + "_at"
    is_string_op := name == host_byte_at_name || name == host_char_at_name || name == string_char_at_name || name == host_slice_name || name == string_slice_name
    if is_string_op {
        if name == host_byte_at_name { value.op = "string_byte_at" }
        if name == host_char_at_name || name == string_char_at_name { value.op = "string_char_at" }
        if name == host_slice_name || name == string_slice_name { value.op = "string_slice" }
        return amd64_emit_string_access(values, value, function_index, position)
    }
    text := ""
    i := 0
    for i < len(value.operands) {
        text = text + "  movq " + amd64_slot(values, value.operands[i]) + ", " + amd64_register(i) + "\n"
        i = i + 1
    }
    target := ".Ls_native_host_args"
    if name == "__std_clock_ns" { target = "s_os_clock_ns" }
    if name == "__std_nanosleep" { target = "s_os_nanosleep" }
    if name == "__host_run_argv" { target = ".Ls_native_run_argv" }
    if name == "__host_same_file" { target = ".Ls_native_same_file" }
    if name == "__host_rename_file" { target = ".Ls_native_rename" }
    if name == "__host_make_temp_dir_in" { target = ".Ls_native_make_temp" }
    if name == "__host_make_executable" { target = ".Ls_native_chmod" }

    if name == "__host_read_to_string" || name == "__host_read_source" { target = ".Ls_native_read_file" }
    if name == "__host_write_text_file" { target = ".Ls_native_write_file" }
    if name == "runtime_env_get" { target = ".Ls_native_env_get" }
    if name == "__host_env_get" { target = ".Ls_native_env_get"; text = text + "  xorl %esi, %esi\n" }
    if name == "__int_to_string" { target = ".Ls_native_int_to_string" }
    if name == "eprintln" || name == "panic" || name == "println" {
        target = ".Ls_native_println"
        descriptor := 2
        if name == "println" { descriptor = 1 }
        text = text + "  movl $" + amd64_integer(descriptor) + ", %esi\n"
    }
    text = text + "  call " + target + "\n"
    if name == "panic" { return text + "  movl $101, %edi\n  movl $60, %eax\n  syscall\n  ud2\n" }
    if value.type_name != "void" { text = text + "  movq %rax, " + amd64_slot(values, value.id) + "\n" }
    return text
}

func amd64_native_intrinsic_runtime() string {
    return ".bss\n.balign 8\n.Ls_native_argc: .quad 0\n.Ls_native_argv: .quad 0\n.Ls_native_envp: .quad 0\n.section .rodata\n.Ls_native_newline: .byte 10\n.text\n.Ls_native_from_c:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n movq %rdi,%r12\n xorl %r13d,%r13d\n.Ls_native_from_c_scan:\n cmpb $0,(%r12,%r13)\n je .Ls_native_from_c_size\n incq %r13\n jmp .Ls_native_from_c_scan\n.Ls_native_from_c_size:\n leaq 8(%r13),%rdi\n call .Ls_native_alloc\n movq %r13,(%rax)\n leaq 8(%rax),%rdi\n movq %r12,%rsi\n movq %r13,%rcx\n cld\n r"
        + "ep movsb\n popq %r13\n popq %r12\n leave\n ret\n.Ls_native_to_c:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n movq %rdi,%r12\n xorl %r13d,%r13d\n testq %r12,%r12\n je .Ls_native_to_c_size\n movq (%r12),%r13\n xorl %ecx,%ecx\n.Ls_native_to_c_check:\n cmpq %r13,%rcx\n jae .Ls_native_to_c_size\n cmpb $0,8(%r12,%rcx)\n je .Ls_native_to_c_fail\n incq %rcx\n jmp .Ls_native_to_c_check\n.Ls_native_to_c_size:\n leaq 1(%r13),%rdi\n call .Ls_native_alloc\n movq %rax,%rdi\n leaq 8(%r12),%rsi\n movq %r13,%rcx\n cld\n rep mov"
        + "sb\n movb $0,(%rdi)\n jmp .Ls_native_to_c_done\n.Ls_native_to_c_fail:\n xorl %eax,%eax\n.Ls_native_to_c_done:\n popq %r13\n popq %r12\n leave\n ret\n.Ls_native_host_args:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n pushq %r14\n pushq %r15\n movq .Ls_native_argc(%rip),%r12\n movq .Ls_native_argv(%rip),%r13\n leaq 8(,%r12,8),%rdi\n call .Ls_native_alloc\n movq %rax,%r15\n movq %r12,(%r15)\n xorl %r14d,%r14d\n.Ls_native_host_args_loop:\n cmpq %r12,%r14\n jae .Ls_native_host_args_done\n movq (%r13,%r14,8),%rdi\n "
        + "call .Ls_native_from_c\n movq %rax,8(%r15,%r14,8)\n incq %r14\n jmp .Ls_native_host_args_loop\n.Ls_native_host_args_done:\n movq %r15,%rax\n popq %r15\n popq %r14\n popq %r13\n popq %r12\n leave\n ret\n.Ls_native_env_get:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n pushq %r14\n pushq %r15\n movq .Ls_native_envp(%rip),%r12\n movq %rdi,%r13\n movq %rsi,%r14\n xorl %r15d,%r15d\n testq %r13,%r13\n je .Ls_native_env_fallback\n movq (%r13),%r15\n testq %r12,%r12\n je .Ls_native_env_fallback\n.Ls_native_env_loop:\n m"
        + "ovq (%r12),%r8\n testq %r8,%r8\n je .Ls_native_env_fallback\n xorl %ecx,%ecx\n.Ls_native_env_match:\n cmpq %r15,%rcx\n jae .Ls_native_env_equal\n movzbl (%r8,%rcx),%eax\n cmpb $0,%al\n je .Ls_native_env_next\n cmpb $61,%al\n je .Ls_native_env_next\n cmpb 8(%r13,%rcx),%al\n jne .Ls_native_env_next\n incq %rcx\n jmp .Ls_native_env_match\n.Ls_native_env_equal:\n cmpb $61,(%r8,%rcx)\n jne .Ls_native_env_next\n leaq 1(%r8,%rcx),%rdi\n call .Ls_native_from_c\n jmp .Ls_native_env_done\n.Ls_native_env_next:\n addq $8,%r12\n jm"
        + "p .Ls_native_env_loop\n.Ls_native_env_fallback:\n movq %r14,%rax\n.Ls_native_env_done:\n popq %r15\n popq %r14\n popq %r13\n popq %r12\n leave\n ret\n.Ls_native_read_file:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n pushq %r14\n pushq %r15\n call .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_read_fail\n movq %rax,%rsi\n movq $-100,%rdi\n xorl %edx,%edx\n xorl %r10d,%r10d\n movl $257,%eax\n syscall\n testq %rax,%rax\n js .Ls_native_read_fail\n movq %rax,%r12\n movq $65536,%r15\n leaq 8(%r15),%rdi\n call .Ls_n"
        + "ative_alloc\n movq %rax,%r13\n xorl %r14d,%r14d\n.Ls_native_read_loop:\n cmpq %r15,%r14\n jb .Ls_native_read_chunk\n movq %r15,%rdi\n shlq $1,%rdi\n jc .Ls_native_read_close_fail\n cmpq %r15,%rdi\n jbe .Ls_native_read_close_fail\n movq %rdi,%r15\n addq $8,%rdi\n jc .Ls_native_read_close_fail\n call .Ls_native_alloc\n movq %rax,%rdi\n addq $8,%rdi\n leaq 8(%r13),%rsi\n movq %r14,%rcx\n cld\n rep movsb\n movq %rax,%r13\n.Ls_native_read_chunk:\n movq %r12,%rdi\n leaq 8(%r13,%r14),%rsi\n movq %r15,%rdx\n subq %r14,%rdx\n xorl"
        + " %eax,%eax\n syscall\n cmpq $-4,%rax\n je .Ls_native_read_chunk\n testq %rax,%rax\n js .Ls_native_read_close_fail\n je .Ls_native_read_finish\n addq %rax,%r14\n jmp .Ls_native_read_loop\n.Ls_native_read_finish:\n movq %r14,(%r13)\n movq %r12,%rdi\n movl $3,%eax\n syscall\n movq %r13,%rax\n jmp .Ls_native_read_done\n.Ls_native_read_close_fail:\n movq %r12,%rdi\n movl $3,%eax\n syscall\n.Ls_native_read_fail:\n xorl %eax,%eax\n.Ls_native_read_done:\n popq %r15\n popq %r14\n popq %r13\n popq %r12\n leave\n ret\n.Ls_native_write"
        + "_file:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n pushq %r14\n pushq %r15\n movq %rsi,%r13\n call .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_write_fail\n movq %rax,%rsi\n movq $-100,%rdi\n movl $577,%edx\n movl $438,%r10d\n movl $257,%eax\n syscall\n testq %rax,%rax\n js .Ls_native_write_fail\n movq %rax,%r12\n xorl %r14d,%r14d\n xorl %r15d,%r15d\n testq %r13,%r13\n je .Ls_native_write_finish\n movq (%r13),%r15\n.Ls_native_write_loop:\n cmpq %r15,%r14\n jae .Ls_native_write_finish\n movq %r12,%rdi\n le"
        + "aq 8(%r13,%r14),%rsi\n movq %r15,%rdx\n subq %r14,%rdx\n movl $1,%eax\n syscall\n cmpq $-4,%rax\n je .Ls_native_write_loop\n testq %rax,%rax\n jle .Ls_native_write_close_fail\n addq %rax,%r14\n jmp .Ls_native_write_loop\n.Ls_native_write_finish:\n movq %r12,%rdi\n movl $3,%eax\n syscall\n testq %rax,%rax\n js .Ls_native_write_fail\n xorl %eax,%eax\n jmp .Ls_native_write_done\n.Ls_native_write_close_fail:\n movq %r12,%rdi\n movl $3,%eax\n syscall\n.Ls_native_write_fail:\n movq $-1,%rax\n.Ls_native_write_done:\n popq %r15\n"
        + " popq %r14\n popq %r13\n popq %r12\n leave\n ret\n.Ls_native_println:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n pushq %r14\n pushq %r15\n movq %rdi,%r12\n movq %rsi,%r13\n xorl %r14d,%r14d\n xorl %r15d,%r15d\n testq %r12,%r12\n je .Ls_native_print_newline\n movq (%r12),%r15\n.Ls_native_print_loop:\n cmpq %r15,%r14\n jae .Ls_native_print_newline\n movq %r13,%rdi\n leaq 8(%r12,%r14),%rsi\n movq %r15,%rdx\n subq %r14,%rdx\n movl $1,%eax\n syscall\n cmpq $-4,%rax\n je .Ls_native_print_loop\n testq %rax,%rax\n jle "
        + ".Ls_native_print_done\n addq %rax,%r14\n jmp .Ls_native_print_loop\n.Ls_native_print_newline:\n movq %r13,%rdi\n leaq .Ls_native_newline(%rip),%rsi\n movl $1,%edx\n movl $1,%eax\n syscall\n cmpq $-4,%rax\n je .Ls_native_print_newline\n.Ls_native_print_done:\n xorl %eax,%eax\n popq %r15\n popq %r14\n popq %r13\n popq %r12\n leave\n ret\n.Ls_native_int_to_string:\n pushq %rbp\n movq %rsp,%rbp\n subq $48,%rsp\n leaq -1(%rbp),%rsi\n movb $0,(%rsi)\n movq %rdi,%rax\n xorl %r8d,%r8d\n testq %rax,%rax\n jns .Ls_native_int_digits\n"
        + " movl $1,%r8d\n negq %rax\n.Ls_native_int_digits:\n movl $10,%r9d\n.Ls_native_int_loop:\n xorl %edx,%edx\n divq %r9\n addb $48,%dl\n decq %rsi\n movb %dl,(%rsi)\n testq %rax,%rax\n jne .Ls_native_int_loop\n testl %r8d,%r8d\n je .Ls_native_int_copy\n decq %rsi\n movb $45,(%rsi)\n.Ls_native_int_copy:\n movq %rsi,%rdi\n call .Ls_native_from_c\n leave\n ret\n.Ls_native_rename:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n movq %rsi,%r13\n call .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_rename_fail\n movq %rax,"
        + "%r12\n movq %r13,%rdi\n call .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_rename_fail\n movq %r12,%rdi\n movq %rax,%rsi\n movl $82,%eax\n syscall\n testq %rax,%rax\n jns .Ls_native_rename_done\n.Ls_native_rename_fail:\n movq $-1,%rax\n.Ls_native_rename_done:\n popq %r13\n popq %r12\n leave\n ret\n.Ls_native_chmod:\n pushq %rbp\n movq %rsp,%rbp\n call .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_chmod_fail\n movq %rax,%rdi\n movl $493,%esi\n movl $90,%eax\n syscall\n testq %rax,%rax\n jns .Ls_native_chmod_done\n.Ls_"
        + "native_chmod_fail:\n movq $-1,%rax\n.Ls_native_chmod_done:\n leave\n ret\n.Ls_native_same_file:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n subq $288,%rsp\n movq %rsi,%r13\n call .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_same_file_false\n movq %rax,%rdi\n leaq -304(%rbp),%rsi\n movl $4,%eax\n syscall\n testq %rax,%rax\n js .Ls_native_same_file_false\n movq %r13,%rdi\n call .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_same_file_false\n movq %rax,%rdi\n leaq -160(%rbp),%rsi\n movl $4,%eax\n syscall"
        + "\n testq %rax,%rax\n js .Ls_native_same_file_false\n movq -304(%rbp),%rdx\n cmpq -160(%rbp),%rdx\n jne .Ls_native_same_file_false\n movq -296(%rbp),%rdx\n cmpq -152(%rbp),%rdx\n jne .Ls_native_same_file_false\n movl $1,%eax\n jmp .Ls_native_same_file_done\n.Ls_native_same_file_false:\n xorl %eax,%eax\n.Ls_native_same_file_done:\n addq $288,%rsp\n popq %r13\n popq %r12\n leave\n ret\n.section .rodata\n.Ls_native_temp_prefix: .ascii \"/s-native-\"\n.Ls_native_hex: .ascii \"0123456789abcdef\"\n.Ls_native_path_key: .quad 4\n "
        + ".ascii \"PATH\"\n.Ls_native_default_path: .quad 13\n .ascii \"/usr/bin:/bin\"\n.text\n.Ls_native_make_temp:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n pushq %r14\n pushq %r15\n subq $16,%rsp\n call .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_make_temp_fail\n movq %rax,%r12\n xorl %r13d,%r13d\n.Ls_native_make_temp_scan:\n cmpb $0,(%r12,%r13)\n je .Ls_native_make_temp_allocate\n incq %r13\n jmp .Ls_native_make_temp_scan\n.Ls_native_make_temp_allocate:\n leaq 27(%r13),%rdi\n call .Ls_native_alloc\n movq %r"
        + "ax,%r14\n movq %rax,%rdi\n movq %r12,%rsi\n movq %r13,%rcx\n cld\n rep movsb\n leaq .Ls_native_temp_prefix(%rip),%rsi\n movl $10,%ecx\n rep movsb\n movl $16,%r15d\n.Ls_native_make_temp_attempt:\n leaq -48(%rbp),%rdi\n movl $8,%esi\n xorl %edx,%edx\n movl $318,%eax\n syscall\n cmpq $-4,%rax\n je .Ls_native_make_temp_attempt\n cmpq $8,%rax\n jne .Ls_native_make_temp_fail\n movq -48(%rbp),%rdx\n leaq 10(%r14,%r13),%rdi\n leaq .Ls_native_hex(%rip),%r8\n movl $16,%ecx\n.Ls_native_make_temp_hex:\n movq %rdx,%rax\n andl $15,%ea"
        + "x\n movzbl (%r8,%rax),%eax\n movb %al,(%rdi)\n incq %rdi\n shrq $4,%rdx\n decl %ecx\n jne .Ls_native_make_temp_hex\n movb $0,(%rdi)\n movq %r14,%rdi\n movl $448,%esi\n movl $83,%eax\n syscall\n testq %rax,%rax\n je .Ls_native_make_temp_success\n cmpq $-17,%rax\n jne .Ls_native_make_temp_fail\n decl %r15d\n jne .Ls_native_make_temp_attempt\n jmp .Ls_native_make_temp_fail\n.Ls_native_make_temp_success:\n movq %r14,%rdi\n call .Ls_native_from_c\n jmp .Ls_native_make_temp_done\n.Ls_native_make_temp_fail:\n xorl %eax,%eax\n."
        + "Ls_native_make_temp_done:\n addq $16,%rsp\n popq %r15\n popq %r14\n popq %r13\n popq %r12\n leave\n ret\n.Ls_native_run_argv:\n pushq %rbp\n movq %rsp,%rbp\n pushq %r12\n pushq %r13\n pushq %r14\n pushq %r15\n subq $32,%rsp\n testq %rdi,%rdi\n je .Ls_native_run_fail\n movq %rdi,%r12\n movq (%r12),%r13\n testq %r13,%r13\n je .Ls_native_run_fail\n leaq 8(,%r13,8),%rdi\n call .Ls_native_alloc\n movq %rax,%r14\n xorl %r15d,%r15d\n.Ls_native_run_convert:\n cmpq %r13,%r15\n jae .Ls_native_run_fork\n movq 8(%r12,%r15,8),%rdi\n call"
        + " .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_run_fail\n movq %rax,(%r14,%r15,8)\n incq %r15\n jmp .Ls_native_run_convert\n.Ls_native_run_fork:\n movq $0,(%r14,%r13,8)\n movl $57,%eax\n syscall\n testq %rax,%rax\n js .Ls_native_run_fail\n je .Ls_native_run_child\n movq %rax,%r12\n.Ls_native_run_wait:\n movq %r12,%rdi\n leaq -64(%rbp),%rsi\n xorl %edx,%edx\n xorl %r10d,%r10d\n movl $61,%eax\n syscall\n cmpq $-4,%rax\n je .Ls_native_run_wait\n testq %rax,%rax\n js .Ls_native_run_fail\n movl -64(%rbp),%eax\n movl %eax,"
        + "%edx\n andl $127,%edx\n jne .Ls_native_run_signal\n shrl $8,%eax\n andl $255,%eax\n jmp .Ls_native_run_done\n.Ls_native_run_signal:\n leal 128(%rdx),%eax\n jmp .Ls_native_run_done\n.Ls_native_run_child:\n movq %r14,%r12\n movq (%r12),%r13\n xorl %ecx,%ecx\n.Ls_native_run_slash:\n movzbl (%r13,%rcx),%eax\n testb %al,%al\n je .Ls_native_run_path\n cmpb $47,%al\n je .Ls_native_run_exec_direct\n incq %rcx\n jmp .Ls_native_run_slash\n.Ls_native_run_exec_direct:\n movq %r13,%rdi\n movq %r12,%rsi\n movq .Ls_native_envp(%rip),"
        + "%rdx\n movl $59,%eax\n syscall\n jmp .Ls_native_run_child_fail\n.Ls_native_run_path:\n movq %rcx,-40(%rbp)\n leaq .Ls_native_path_key(%rip),%rdi\n leaq .Ls_native_default_path(%rip),%rsi\n call .Ls_native_env_get\n movq %rax,%rdi\n call .Ls_native_to_c\n testq %rax,%rax\n je .Ls_native_run_child_fail\n movq %rax,%r14\n.Ls_native_run_path_component:\n movq %r14,%r15\n.Ls_native_run_path_scan:\n cmpb $0,(%r14)\n je .Ls_native_run_path_allocate\n cmpb $58,(%r14)\n je .Ls_native_run_path_allocate\n incq %r14\n jmp .Ls_na"
        + "tive_run_path_scan\n.Ls_native_run_path_allocate:\n movq %r14,%rax\n subq %r15,%rax\n movq %rax,-48(%rbp)\n movq %rax,%rdi\n addq -40(%rbp),%rdi\n addq $2,%rdi\n call .Ls_native_alloc\n movq %rax,-56(%rbp)\n movq %rax,%rdi\n movq %r15,%rsi\n movq -48(%rbp),%rcx\n cld\n rep movsb\n cmpq $0,-48(%rbp)\n je .Ls_native_run_path_name\n movb $47,(%rdi)\n incq %rdi\n.Ls_native_run_path_name:\n movq %r13,%rsi\n movq -40(%rbp),%rcx\n incq %rcx\n rep movsb\n movq -56(%rbp),%rdi\n movq %r12,%rsi\n movq .Ls_native_envp(%rip),%rdx\n mo"
        + "vl $59,%eax\n syscall\n cmpb $0,(%r14)\n je .Ls_native_run_child_fail\n incq %r14\n jmp .Ls_native_run_path_component\n.Ls_native_run_child_fail:\n movl $127,%edi\n movl $60,%eax\n syscall\n ud2\n.Ls_native_run_fail:\n movq $-1,%rax\n.Ls_native_run_done:\n addq $32,%rsp\n popq %r15\n popq %r14\n popq %r13\n popq %r12\n leave\n ret\n"
        + amd64_os_runtime()
}

func amd64_global_name(int index) string { return ".Ls_native_global_" + amd64_integer(index) }
func amd64_emit_global(function_ssa_program program, function_ssa_value[] values, function_ssa_value value) string {
    symbol := amd64_global_name(ssa_global_index(program.globals, value.symbol))
    slot := amd64_slot(values, value.id)
    if value.op == "global_get" { return "  movq " + symbol + "(%rip), %rax\n  movq %rax, " + slot + "\n" }
    return "  movq " + amd64_slot(values, value.operands[0]) + ", %rax\n  movq %rax, " + symbol + "(%rip)\n  movq $0, " + slot + "\n"
}
func amd64_emit_global_initializers(function_ssa_program program) string {
    text := ".bss\n.balign 8\n.globl s_native_gc_roots_begin\ns_native_gc_roots_begin:\n.Ls_native_globals_state: .quad 0\n"
    g := 0
    for g < len(program.globals) {
        text = text + amd64_global_name(g) + ": .quad 0\n"
        g = g + 1
    }
    text = text + ".globl s_native_gc_roots_end\ns_native_gc_roots_end:\n.text\n.globl s_native_initialize_globals\n.type s_native_initialize_globals, @function\ns_native_initialize_globals:\n  pushq %rbp\n  movq %rsp, %rbp\n  cmpq $2, .Ls_native_globals_state(%rip)\n  je .Ls_native_globals_done\n  cmpq $0, .Ls_native_globals_state(%rip)\n  jne .Ls_native_globals_cycle\n  movq $1, .Ls_native_globals_state(%rip)\n"
    order := ssa_global_order(program)
    i := 0
    for i < len(order.order) {
        index := order.order[i]
        initializer := program.globals[index].initializer
        if initializer != "" {
            target := ssa_function_index(program.functions, initializer)
            text = text + "  call " + amd64_function_name(target) + "\n  movq %rax, " + amd64_global_name(index) + "(%rip)\n"
        }
        i = i + 1
    }
    return text + "  movq $2, .Ls_native_globals_state(%rip)\n.Ls_native_globals_done:\n  xorl %eax, %eax\n  leave\n  ret\n.Ls_native_globals_cycle:\n  movl $88, %edi\n  movl $60, %eax\n  syscall\n  ud2\n.size s_native_initialize_globals, .-s_native_initialize_globals\n"
}

// BEGIN GENERATED NATIVE OS
func amd64_os_runtime() string {
    return "# Shared freestanding OS boundary. SysV AMD64 arguments/results; negative errno.\n# Generated into canonical runtime text and the seed runtime by generate-native-os.py.\n.text\n.global s_os_clock_ns\n.type s_os_clock_ns, @function\ns_os_clock_ns:\n    cmp $1, %r"
        + "di\n    ja .Los_clock_invalid\n    sub $16, %rsp\n    mov %rsp, %rsi\n    mov $228, %eax\n    syscall\n    test %rax, %rax\n    js .Los_clock_done\n    mov (%rsp), %rax\n    test %rax, %rax\n    js .Los_clock_overflow\n    imul $1000000000, %rax, %rax\n    jo .Los_clo"
        + "ck_overflow\n    add 8(%rsp), %rax\n    jo .Los_clock_overflow\n.Los_clock_done:\n    add $16, %rsp\n    ret\n.Los_clock_overflow:\n    mov $-75, %rax\n    jmp .Los_clock_done\n.Los_clock_invalid:\n    mov $-22, %rax\n    ret\n.size s_os_clock_ns, .-s_os_clock_ns\n\n.gl"
        + "obal s_os_nanosleep\n.type s_os_nanosleep, @function\ns_os_nanosleep:\n    # Validate even direct intrinsic callers before exposing stack timespecs.\n    test %rdi, %rdi\n    js .Los_sleep_invalid\n    cmp $1000000000, %rsi\n    jae .Los_sleep_invalid\n    sub $32"
        + ", %rsp\n    mov %rdi, (%rsp)\n    mov %rsi, 8(%rsp)\n.Los_sleep_retry:\n    # Initialize remaining=request as a safe fallback for injected EINTR.\n    mov (%rsp), %rax\n    mov %rax, 16(%rsp)\n    mov 8(%rsp), %rax\n    mov %rax, 24(%rsp)\n    mov %rsp, %rdi\n    le"
        + "a 16(%rsp), %rsi\n    mov $35, %eax\n    syscall\n    cmp $-4, %rax\n    jne .Los_sleep_done\n    mov 16(%rsp), %rax\n    mov %rax, (%rsp)\n    mov 24(%rsp), %rax\n    mov %rax, 8(%rsp)\n    jmp .Los_sleep_retry\n.Los_sleep_done:\n    add $32, %rsp\n    ret\n.Los_sleep"
        + "_invalid:\n    mov $-22, %rax\n    ret\n.size s_os_nanosleep, .-s_os_nanosleep\n"
}
// END GENERATED NATIVE OS
