package compile.internal


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
            if count != 1 { return "amd64: missing or duplicate parameter" }
            p = p + 1
        }
        b := 0
        for b < len(function_data.blocks) {
            v := 0
            for v < len(function_data.blocks[b].values) {
                value := function_data.blocks[b].values[v]
                op := value.op
                supported := ssa_is_scalar_operation(op) || op == "param" || op == "phi" || op == "const_int" || op == "const_unit" || op == "copy" || op == "add" || op == "sub" || op == "mul" || op == "div" || op == "mod" || op == "call" || op == "record_new" || op == "record_get" || op == "record_set" || op == "array_new" || op == "array_get" || op == "array_len" || op == "array_append" || op == "array_set"
                if !supported { return "amd64: unsupported operation: " + op }
                if !ssa_type_supported(value.type_name, program.records) && !(op == "call" && value.type_name == "void") { return "amd64: unsupported value type" }
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
    slot := amd64_slot(values, value.id)
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
        i := 0
        for i < len(record.field_names) {
            offset := amd64_integer(i * 8)
            text = text + "  movq " + offset + "(%r8), %r10\n  movq %r10, " + offset + "(%rax)\n"
            i = i + 1
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
    position := 0
    b := 0
    for b < len(function_data.blocks) {
        block := function_data.blocks[b]
        text = text + amd64_block_label(index, block.id) + ":\n"
        v = 0
        for v < len(block.values) {
            if block.values[v].op != "phi" { text = text + amd64_emit_value_with_values(program, index, position, values) }
            position = position + 1
            v = v + 1
        }
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
        b = b + 1
    }
    return text + ".size " + name + ", .-" + name + "\n"
}

func emit_function_ssa_amd64(function_ssa_program program) amd64_program_result {
    error := amd64_validate_program(program)
    if error != "" { return amd64_fail(error) }
    text := ".text\n"
    f := 0
    for f < len(program.functions) {
        text = text + amd64_emit_function(program, f)
        f = f + 1
    }
    entry_index := ssa_function_index(program.functions, program.entry_symbol)
    text = text + ".globl s_native_entry\n.type s_native_entry, @function\ns_native_entry:\n  jmp " + amd64_function_name(entry_index) + "\n.size s_native_entry, .-s_native_entry\n"
        + ".Ls_native_divzero:\n  movl $86, %edi\n  movl $60, %eax\n  syscall\n  ud2\n"
        + ".section .note.GNU-stack,\"\",@progbits\n"
    if amd64_needs_arena(program) { text = text + amd64_record_allocator() }
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

// Native records live in a process-lifetime bump arena. Fresh mmap pages are
// zero-filled, including unspecified fields. No host compiler/runtime is used.
func amd64_record_allocator() string {
    return ".bss\n.align 8\n.Ls_native_heap_next: .quad 0\n.Ls_native_heap_end: .quad 0\n.text\n.Ls_native_alloc:\n"
        + "  pushq %rbx\n  movq %rdi, %rbx\n  addq $7, %rbx\n  andq $-8, %rbx\n"
        + "  movq .Ls_native_heap_next(%rip), %rax\n  leaq (%rax,%rbx), %rdx\n  cmpq .Ls_native_heap_end(%rip), %rdx\n  jbe .Ls_native_alloc_have\n"
        + "  movq %rbx, %rsi\n  addq $65535, %rsi\n  andq $-65536, %rsi\n"
        + "  xorl %edi, %edi\n  movl $3, %edx\n  movl $34, %r10d\n  movq $-1, %r8\n  xorl %r9d, %r9d\n  movl $9, %eax\n  syscall\n"
        + "  cmpq $-4095, %rax\n  jae .Ls_native_alloc_fail\n  leaq (%rax,%rsi), %rdx\n  movq %rdx, .Ls_native_heap_end(%rip)\n  leaq (%rax,%rbx), %rdx\n"
        + ".Ls_native_alloc_have:\n  movq %rdx, .Ls_native_heap_next(%rip)\n  popq %rbx\n  ret\n"
        + ".Ls_native_alloc_fail:\n  movl $126, %edi\n  movl $60, %eax\n  syscall\n  ud2\n"
}

func amd64_needs_arena(function_ssa_program program) bool {
    f := 0
    for f < len(program.functions) {
        b := 0
        for b < len(program.functions[f].blocks) {
            v := 0
            for v < len(program.functions[f].blocks[b].values) {
                op := program.functions[f].blocks[b].values[v].op
                if op == "record_new" || op == "record_set" || op == "array_new" || op == "array_append" || op == "array_set" { return true }
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
