
func arm64_asm_argument_pop(int index) string {
    if index == 0 { return "    ldr x0, [sp], #16\n" }
    if index == 1 { return "    ldr x1, [sp], #16\n" }
    if index == 2 { return "    ldr x2, [sp], #16\n" }
    if index == 3 { return "    ldr x3, [sp], #16\n" }
    if index == 4 { return "    ldr x4, [sp], #16\n" }
    if index == 5 { return "    ldr x5, [sp], #16\n" }
    return ""
}

func arm64_asm_call_arguments(string source, int raw_start, int end, string function_name, int index) string {
    int start = skip_space(source, raw_start)
    if start >= end || index >= 6 { return "" }
    int comma = argument_comma(source, start, end)
    int argument_end = end
    if comma >= 0 { argument_end = comma }
    string value = arm64_asm_expression(source, start, argument_end, function_name)
    if value == "" { return "" }
    if comma < 0 {
        return value + "    str x0, [sp, #-16]!\n" + arm64_asm_argument_pop(index)
    }
    string remaining = arm64_asm_call_arguments(source, comma + 1, end, function_name, index + 1)
    if remaining == "" { return "" }
    return value + "    str x0, [sp, #-16]!\n" + remaining + arm64_asm_argument_pop(index)
}

func arm64_asm_expression(string source, int raw_start, int raw_end, string function_name) string {
    int start = skip_space(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return "" }
    if __host_char_at(source, start) == "(" {
        int close = matching_paren(source, start, end)
        if close == end - 1 { return arm64_asm_expression(source, start + 1, end - 1, function_name) }
    }
    int operator_at = arithmetic_operator_at(source, start, end, false)
    if operator_at < 0 { operator_at = arithmetic_operator_at(source, start, end, true) }
    if operator_at >= 0 {
        string left = arm64_asm_expression(source, start, operator_at, function_name)
        string right = arm64_asm_expression(source, operator_at + 1, end, function_name)
        if left == "" || right == "" { return "" }
        string op = __host_char_at(source, operator_at)
        if op == "+" {
            return left + "    str x0, [sp, #-16]!\n" + right + "    ldr x1, [sp], #16\n    add x0, x1, x0\n    sub x0, x0, #1\n"
        }
        if op == "-" {
            return left + "    str x0, [sp, #-16]!\n" + right + "    ldr x1, [sp], #16\n    sub x0, x1, x0\n    add x0, x0, x0\n    add x0, x0, #1\n"
        }
        return ""
    }
    int number_end = skip_uint(source, start)
    if number_end == end {
        return "    mov x0, #" + int_text(parse_uint(source, start)) + "\n    lsl x0, x0, #1\n    add x0, x0, #1\n"
    }
    int name_end = skip_identifier(source, start)
    string name = __host_slice(source, start, name_end)
    if name_end == end {
        int parameter = function_parameter_index(source, function_name, name)
        if parameter >= 0 && parameter < 6 {
            return "    ldur x0, [x29, #" + signed_int_text(0 - ((parameter + 1) * 8)) + "]\n"
        }
        return ""
    }
    int open = skip_space(source, name_end)
    if name_end > start && open < end && __host_char_at(source, open) == "(" {
        int close = matching_paren(source, open, end)
        if close != end - 1 { return "" }
        string arguments = ""
        int argument_start = skip_space(source, open + 1)
        if argument_start < close {
            arguments = arm64_asm_call_arguments(source, argument_start, close, function_name, 0)
            if arguments == "" { return "" }
        } else if function_parameter(source, name) != "" { return "" }
        return arguments + "    bl _s_fn_" + name + "\n"
    }
    return ""
}

func arm64_asm_function(string source, string name) string {
    int body = function_body(source, name)
    int body_end = function_body_end(source, body + 1)
    if body < 0 || body_end < 0 { return "" }
    int statement = skip_space(source, body + 1)
    if statement >= body_end || !matches_at(source, statement, "return") { return "" }
    int expression = skip_space(source, statement + 6)
    int expression_end = expression_end(source, expression)
    if expression_end < 0 || expression_end > body_end { return "" }
    int after = expression_end
    if after < body_end && __host_char_at(source, after) == ";" { after = after + 1 }
    if skip_space(source, after) != body_end { return "" }
    string body_code = arm64_asm_expression(source, expression, expression_end, name)
    if body_code == "" { return "" }
    string code = ".globl _s_fn_" + name + "\n.p2align 2\n_s_fn_" + name + ":\n    stp x29, x30, [sp, #-16]!\n    mov x29, sp\n    sub sp, sp, #64\n"
    int parameter = 0
    for parameter < 6 && function_parameter_at(source, name, parameter) != "" {
        code = code + "    stur x" + int_text(parameter) + ", [x29, #" + signed_int_text(0 - ((parameter + 1) * 8)) + "]\n"
        parameter = parameter + 1
    }
    return code + body_code + "    add sp, sp, #64\n    ldp x29, x30, [sp], #16\n    ret\n\n"
}

func emit_darwin_arm64_assembly(string source) string {
    string output = ".section __TEXT,__text,regular,pure_instructions\n.globl _start\n.p2align 2\n_start:\n    bl _s_fn_main\n    tbnz x0, #0, 1f\n    mov x0, #0\n    b 2f\n1:\n    asr x0, x0, #1\n2:\n    bl _exit\n    brk #0\n\n"
    int index = 0
    int emitted = 0
    for index < len(source) {
        int declaration = find_function_from(source, index)
        if declaration < 0 { break }
        int name_at = skip_space(source, declaration + 4)
        int name_end = skip_identifier(source, name_at)
        string name = __host_slice(source, name_at, name_end)
        string function_code = arm64_asm_function(source, name)
        if function_code == "" { return "" }
        output = output + function_code
        emitted = emitted + 1
        index = name_end
    }
    if emitted == 0 || function_declaration(source, "main") < 0 { return "" }
    return output
}

func compile_darwin_arm64_assembly(string source, string output_path) int {
    string assembly = emit_darwin_arm64_assembly(source)
    if assembly == "" {
        eprintln("compile: source is outside Darwin/arm64 bootstrap assembly slice")
        return 1
    }
    if __host_write_text_file(output_path, assembly) != 0 {
        eprintln("compile: cannot write Darwin/arm64 assembly output")
