package compile.internal


// This is instruction selection, not an interpreter or a C source producer.
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
    // Positions, not arbitrary SSA IDs, determine the frame size and offsets.
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
        symbol := function_data.symbol
        if len(function_data.blocks) != 1 { return "amd64: only single-block functions supported: " + symbol }
        block := function_data.blocks[0]
        if block.terminator != "return" || len(block.predecessors) != 0 || len(block.successors) != 0 {
            return "amd64: only straight-line return supported: " + symbol
        }
        if len(function_data.result_types) > 1 { return "amd64: multiple results unsupported: " + symbol }
        if len(function_data.result_types) == 1 && function_data.result_types[0] != "int" && function_data.result_types[0] != "()" {
            return "amd64: unsupported result type: " + symbol
        }
        p := 0
        for p < len(function_data.parameter_types) {
            if function_data.parameter_types[p] != "int" && function_data.parameter_types[p] != "()" { return "amd64: unsupported parameter type: " + symbol }
            count := 0
            v := 0
            for v < len(block.values) {
                if block.values[v].op == "param" && block.values[v].parameter_index == p { count = count + 1 }
                v = v + 1
            }
            if count != 1 { return "amd64: missing or duplicate parameter: " + symbol }
            p = p + 1
        }
        v := 0
        for v < len(block.values) {
            value := block.values[v]
            op := value.op
            if op != "param" && op != "const_int" && op != "const_unit" && op != "copy" && op != "add" && op != "sub" && op != "mul" && op != "div" && op != "mod" && op != "call" {
                return "amd64: unsupported operation: " + op
            }
            if value.type_name != "int" && value.type_name != "()" && !(op == "call" && value.type_name == "void") {
                return "amd64: unsupported value type: " + symbol
            }
            if op == "param" {
                if value.parameter_index < 0 || value.parameter_index >= len(function_data.parameter_types) {
                    return "amd64: invalid parameter index: " + symbol
                }
                if value.type_name != function_data.parameter_types[value.parameter_index] { return "amd64: parameter type: " + symbol }
            }
            if (op == "param" || op == "const_int" || op == "const_unit") && len(value.operands) != 0 {
                return "amd64: unexpected operands: " + symbol
            }
            if op == "const_unit" && (value.type_name != "()" || value.integer_value != 0) { return "amd64: invalid unit constant" }
            if op == "const_int" && value.type_name != "int" { return "amd64: invalid integer constant" }
            if (op == "add" || op == "sub" || op == "mul" || op == "div" || op == "mod") && value.type_name != "int" { return "amd64: arithmetic result type: " + symbol }
            if op == "copy" && len(value.operands) != 1 { return "amd64: copy operand count: " + symbol }
            if (op == "add" || op == "sub" || op == "mul" || op == "div" || op == "mod") && len(value.operands) != 2 {
                return "amd64: arithmetic operand count: " + symbol
            }
            a := 0
            for a < len(value.operands) {
                operand_type := ssa_value_type(function_data.blocks, value.operands[a])
                if op == "copy" && operand_type != value.type_name { return "amd64: copy type mismatch: " + symbol }
                if op != "copy" && op != "call" && operand_type != "int" {
                    return "amd64: unsupported operand type: " + symbol
                }
                a = a + 1
            }
            v = v + 1
        }
        f = f + 1
    }
    return ""
}

func amd64_emit_call(function_ssa_program program, function_ssa_function function_data, function_ssa_value value) string {
    values := function_data.blocks[0].values
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
    target := amd64_call_target(program, function_data.symbol, function_data.blocks[0].id, value.id)
    text = text + "  call " + amd64_function_name(target) + "\n"
    cleanup := (stack_count + padding) * 8
    if cleanup > 0 { text = text + "  addq $" + amd64_integer(cleanup) + ", %rsp\n" }
    if value.type_name == "int" || value.type_name == "()" { text = text + "  movq %rax, " + amd64_slot(values, value.id) + "\n" }
    return text
}

func amd64_emit_value(function_ssa_program program, int function_index, int position) string {
    function_data := program.functions[function_index]
    values := function_data.blocks[0].values
    value := values[position]
    op := value.op
    if op == "param" { return "" }
    slot := amd64_slot(values, value.id)
    if op == "const_unit" { return "  movq $0, " + slot + "\n" }
    if op == "const_int" {
        return "  movabsq $" + amd64_integer(value.integer_value) + ", %rax\n  movq %rax, " + slot + "\n"
    }
    if op == "call" { return amd64_emit_call(program, function_data, value) }
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

func amd64_emit_function(function_ssa_program program, int index) string {
    function_data := program.functions[index]
    block := function_data.blocks[0]
    name := amd64_function_name(index)
    frame_size := ((len(block.values) * 8 + 15) / 16) * 16
    text := ".globl " + name + "\n.type " + name + ", @function\n" + name + ":\n  pushq %rbp\n  movq %rsp, %rbp\n"
    if frame_size > 0 { text = text + "  subq $" + amd64_integer(frame_size) + ", %rsp\n" }
    // Capture every incoming register before any arithmetic or call can
    // clobber it. Parameter values need not occur in ABI order in the block.
    v := 0
    for v < len(block.values) {
        value := block.values[v]
        if value.op == "param" {
            source := amd64_register(value.parameter_index)
            if value.parameter_index >= 6 {
                source = amd64_integer(16 + (value.parameter_index - 6) * 8) + "(%rbp)"
                text = text + "  movq " + source + ", %rax\n"
                source = "%rax"
            }
            text = text + "  movq " + source + ", " + amd64_slot(block.values, value.id) + "\n"
        }
        v = v + 1
    }
    v = 0
    for v < len(block.values) {
        text = text + amd64_emit_value(program, index, v)
        v = v + 1
    }
    if len(block.terminator_values) == 1 {
        text = text + "  movq " + amd64_slot(block.values, block.terminator_values[0]) + ", %rax\n"
    } else {
        text = text + "  xorl %eax, %eax\n"
    }
    return text + "  leave\n  ret\n.size " + name + ", .-" + name + "\n"
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
    return amd64_program_result { assembly: text, error: "" }
}

func amd64_executable_startup(function_ssa_program program) amd64_program_result {
    error := amd64_validate_program(program)
    if error != "" { return amd64_fail(error) }
    entry := program.functions[ssa_function_index(program.functions, program.entry_symbol)]
    if len(entry.parameter_types) > 1 { return amd64_fail("amd64 startup: entry must have zero or one int parameter") }
    text := ".text\n.globl _start\n.type _start, @function\n_start:\n"
    if len(entry.parameter_types) == 1 {
        // Accumulate a negative number: the negative range includes INT64_MIN.
        // Compare before each multiply/subtract, with sign-specific last digit.
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
