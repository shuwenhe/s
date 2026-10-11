func emit_native_auto_elf(string source) string {
    string elf = emit_native_copy_elf(source)
    if elf != "" { return elf }
    elf = emit_native_loop_elf(source)
    if elf != "" { return elf }
    elf = emit_native_string_elf(source)
    if elf != "" { return elf }
    elf = emit_native_array_elf(source)
    if elf != "" { return elf }
    elf = emit_native_call_elf(source)
    if elf != "" { return elf }
    elf = emit_native_multi_call_elf(source)
    if elf != "" { return elf }
    elf = emit_native_control_elf(source)
    if elf != "" { return elf }
    elf = emit_native_locals_elf(source)
    if elf != "" { return elf }
    return emit_native_expression_elf(source)
}

func asm_argument_pop(int index) string {
    if index == 0 { return "    pop %rdi\n" }
    if index == 1 { return "    pop %rsi\n" }
    if index == 2 { return "    pop %rdx\n" }
    if index == 3 { return "    pop %rcx\n" }
    if index == 4 { return "    pop %r8\n" }
    if index == 5 { return "    pop %r9\n" }
    return ""
}

func asm_runtime_callee(string name) string {
    if name == "len" { return "s_value_len" }
    if name == "host_args" { return "s_host_args_value" }
    if name == "eprintln" { return "s_eprintln_value" }
    if name == "__host_char_at" { return "s_string_char_at" }
    if name == "__host_byte_at" { return "s_string_byte_at" }
    if name == "__host_slice" { return "s_string_slice" }
    if name == "__host_byte_string" { return "s_byte_string_value" }
    if name == "__host_read_to_string" { return "s_read_file_value" }
    if name == "__host_write_text_file" { return "s_write_file_value" }
    if name == "__host_make_executable" { return "s_make_executable_value" }
    return "s_fn_" + name
}

func asm_local_load(string source, string function_name, int before, string name) string {
    int parameter = function_parameter_index(source, function_name, name)
    if parameter >= 0 && parameter < 6 {
        return "    mov " + signed_int_text(0 - ((parameter + 1) * 8)) + "(%rbp), %rax\n"
    }
    int body = function_body(source, function_name)
    int slot = local_slot(source, body, before, name)
    if slot < 0 { return "" }
    return "    mov " + signed_int_text(0 - ((slot + 7) * 8)) + "(%rbp), %rax\n"
}

func asm_local_store(string source, string function_name, int before, string name) string {
    int body = function_body(source, function_name)
    int slot = local_slot(source, body, before, name)
    if slot < 0 { return "" }
    return "    mov %rax, " + signed_int_text(0 - ((slot + 7) * 8)) + "(%rbp)\n"
}

func asm_call_arguments(string source, int raw_start, int end, string function_name, int index) string {
    int start = skip_space(source, raw_start)
    if start >= end || index >= 6 { return "" }
    int comma = argument_comma(source, start, end)
    int argument_end = end
    if comma >= 0 { argument_end = comma }
    string value = asm_expression(source, start, argument_end, function_name)
    if value == "" { return "" }
    if comma < 0 {
        return value + "    push %rax\n" + asm_argument_pop(index)
    }
    string remaining = asm_call_arguments(source, comma + 1, end, function_name, index + 1)
    if remaining == "" { return "" }
    return value + "    push %rax\n" + remaining + asm_argument_pop(index)
}

func asm_comparison(string operator) string {
    if operator == "==" { return "    sete %al\n" }
    if operator == "!=" { return "    setne %al\n" }
    if operator == "<" { return "    setl %al\n" }
    if operator == "<=" { return "    setle %al\n" }
    if operator == ">" { return "    setg %al\n" }
    return "    setge %al\n"
}

func asm_expression(string source, int raw_start, int raw_end, string function_name) string {
    int start = skip_space(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return "" }
    if __host_char_at(source, start) == "(" {
        int close = matching_paren(source, start, end)
        if close == end - 1 { return asm_expression(source, start + 1, end - 1, function_name) }
    }
    if __host_char_at(source, start) == "-" {
        string negated = asm_expression(source, start + 1, end, function_name)
        if negated == "" { return "" }
        return negated + "    sar $1, %rax\n    neg %rax\n    lea 1(%rax,%rax), %rax\n"
    }
    int logical = logical_at(source, start, end, "||")
    if logical >= 0 {
        string left_or = asm_expression(source, start, logical, function_name)
        string right_or = asm_expression(source, logical + 2, end, function_name)
        if left_or == "" || right_or == "" { return "" }
        string or_label = int_text(logical)
        string code = left_or + "    cmp $1, %rax\n    jne .Las_or_done_" + or_label + "\n"
        code = code + right_or + ".Las_or_done_" + or_label + ":\n"
        return code
    }
    logical = logical_at(source, start, end, "&&")
    if logical >= 0 {
        string left_and = asm_expression(source, start, logical, function_name)
        string right_and = asm_expression(source, logical + 2, end, function_name)
        if left_and == "" || right_and == "" { return "" }
        string and_label = int_text(logical)
        string code = left_and + "    cmp $1, %rax\n    je .Las_and_done_" + and_label + "\n"
        code = code + right_and + ".Las_and_done_" + and_label + ":\n"
        return code
    }
    if __host_char_at(source, start) == "!" &&
        (start + 1 >= end || __host_char_at(source, start + 1) != "=") {
        string not_value = asm_expression(source, start + 1, end, function_name)
        if not_value == "" { return "" }
        return not_value + "    cmp $1, %rax\n    sete %al\n    movzbq %al, %rax\n    lea 1(%rax,%rax), %rax\n"
    }
    int compare = comparison_at(source, start, end)
    if compare >= 0 {
        int operator_end = compare + 1
        if operator_end < end && __host_char_at(source, operator_end) == "=" { operator_end = operator_end + 1 }
        string operator = __host_slice(source, compare, operator_end)
        string left_compare = asm_expression(source, start, compare, function_name)
        string right_compare = asm_expression(source, operator_end, end, function_name)
        if left_compare == "" || right_compare == "" { return "" }
        string code = left_compare + "    push %rax\n" + right_compare
        code = code + "    mov %rax, %rsi\n    pop %rdi\n    call s_value_cmp\n    cmp $0, %rax\n"
        code = code + asm_comparison(operator) + "    movzbq %al, %rax\n    lea 1(%rax,%rax), %rax\n"
        return code
    }
    int operator_at = arithmetic_operator_at(source, start, end, false)
    if operator_at < 0 { operator_at = arithmetic_operator_at(source, start, end, true) }
    if operator_at >= 0 {
        string left = asm_expression(source, start, operator_at, function_name)
        string right = asm_expression(source, operator_at + 1, end, function_name)
        if left == "" || right == "" { return "" }
        string operator = __host_char_at(source, operator_at)
        if operator == "+" {
            string code = left + "    push %rax\n" + right
            code = code + "    mov %rax, %rsi\n    pop %rdi\n    call s_value_add\n"
            return code
        }
        string arithmetic = "    sar $1, %rax\n    mov %rax, %rcx\n    pop %rax\n    sar $1, %rax\n"
        if operator == "-" { arithmetic = arithmetic + "    sub %rcx, %rax\n" }
        if operator == "*" { arithmetic = arithmetic + "    imul %rcx, %rax\n" }
        if operator == "/" { arithmetic = arithmetic + "    cqo\n    idiv %rcx\n" }
        if operator == "%" { arithmetic = arithmetic + "    cqo\n    idiv %rcx\n    mov %rdx, %rax\n" }
        return left + "    push %rax\n" + right + arithmetic + "    lea 1(%rax,%rax), %rax\n"
    }
    if __host_char_at(source, start) == "\"" {
        int quote = start + 1
        for quote < end {
            if __host_char_at(source, quote) == "\\" { quote = quote + 2; continue }
            if __host_char_at(source, quote) == "\"" { break }
            quote = quote + 1
        }
        if quote == end - 1 { return "    lea .Las_string_" + int_text(start) + "(%rip), %rax\n" }
    }
    int number_end = skip_uint(source, start)
    if number_end == end {
        return "    mov $" + int_text(parse_uint(source, start) * 2 + 1) + ", %rax\n"
    }
    int name_end = skip_identifier(source, start)
    string name = __host_slice(source, start, name_end)
    if name_end == end && name == "true" { return "    mov $3, %rax\n" }
    if name_end == end && name == "false" { return "    mov $1, %rax\n" }
    if name_end == end { return asm_local_load(source, function_name, start, name) }
    int open = skip_space(source, name_end)
    if open < end && __host_char_at(source, open) == "[" {
        int close_index = matching_square(source, open, end)
        if close_index != end - 1 { return "" }
        string collection = asm_local_load(source, function_name, start, name)
        string subscript = asm_expression(source, open + 1, close_index, function_name)
        if collection == "" || subscript == "" { return "" }
        string code = collection + "    push %rax\n" + subscript
        code = code + "    mov %rax, %rsi\n    pop %rdi\n    call s_index_get\n"
        return code
    }
    if open >= end || __host_char_at(source, open) != "(" { return "" }
    int close = matching_paren(source, open, end)
    if close != end - 1 { return "" }
    string arguments = ""
    int argument_start = skip_space(source, open + 1)
    if argument_start < close {
        arguments = asm_call_arguments(source, argument_start, close, function_name, 0)
        if arguments == "" { return "" }
    }
    return arguments + "    call " + asm_runtime_callee(name) + "\n"
}

func asm_if_statement_end(string source, int start, int block_end) int {
    if start >= block_end || !matches_at(source, start, "if") { return -1 }
    int open = skip_space(source, start + 2)
    int depth = 0
    for open < block_end {
        string ch = __host_char_at(source, open)
        if ch == "\"" {
            open = skip_quoted(source, open, block_end)
            continue
        }
        if ch == "(" { depth = depth + 1 }
        if ch == ")" { depth = depth - 1 }
        if ch == "{" && depth == 0 { break }
        open = open + 1
    }
    if open >= block_end { return -1 }
    int close = function_body_end(source, open + 1)
    if close < 0 || close >= block_end { return -1 }
    int after = skip_trivia(source, close + 1)
    if after >= block_end || !matches_at(source, after, "else") { return close + 1 }
    int alternative = skip_space(source, after + 4)
    if alternative < block_end && matches_at(source, alternative, "if") {
        return asm_if_statement_end(source, alternative, block_end)
    }
    if alternative >= block_end || __host_char_at(source, alternative) != "{" { return -1 }
    int alternative_end = function_body_end(source, alternative + 1)
    if alternative_end < 0 || alternative_end >= block_end { return -1 }
    return alternative_end + 1
}

func asm_block_loop(string source, int raw_start, int block_end, string function_name, string loop_start, string loop_end) string {
    int index = skip_trivia(source, raw_start)
    if index >= block_end { return "" }
    if matches_at(source, index, "return") {
        int result_start = skip_space(source, index + 6)
        int result_end = expression_end(source, result_start)
        string result = asm_expression(source, result_start, result_end, function_name)
        if result_end < 0 || result_end > block_end || result == "" { return "" }
        return result + "    jmp .Las_return_" + function_name + "\n"
    }
    if matches_at(source, index, "break") {
        if loop_end == "" { return "" }
        return "    jmp " + loop_end + "\n"
    }
    if matches_at(source, index, "continue") {
        if loop_start == "" { return "" }
        return "    jmp " + loop_start + "\n"
    }
    if matches_at(source, index, "if") {
        int condition_start = skip_space(source, index + 2)
        int open = condition_start
        int depth = 0
        for open < block_end {
            string ch = __host_char_at(source, open)
            if ch == "\"" {
                open = skip_quoted(source, open, block_end)
                continue
            }
            if ch == "(" { depth = depth + 1 }
            if ch == ")" { depth = depth - 1 }
            if ch == "{" && depth == 0 { break }
            open = open + 1
        }
        if open >= block_end { return "" }
        int close = function_body_end(source, open + 1)
        if close < 0 || close > block_end { return "" }
        string condition = asm_expression(source, condition_start, open, function_name)
        string then_code = asm_block_loop(source, open + 1, close, function_name, loop_start, loop_end)
        if condition == "" { return "" }
        string label = int_text(index)
        int after = skip_trivia(source, close + 1)
        if after < block_end && matches_at(source, after, "else") {
            int else_open = skip_space(source, after + 4)
            if else_open < block_end && matches_at(source, else_open, "if") {
                int else_if_end = asm_if_statement_end(source, else_open, block_end)
                if else_if_end < 0 { return "" }
                string else_if_code = asm_block_loop(source, else_open, else_if_end, function_name, loop_start, loop_end)
                string rest_after_else_if = asm_block_loop(source, else_if_end, block_end, function_name, loop_start, loop_end)
                if else_if_code == "" { return "" }
                string code = condition + "    cmp $1, %rax\n    je .Las_else_" + label + "\n"
                code = code + then_code + "    jmp .Las_if_done_" + label + "\n.Las_else_" + label + ":\n"
                code = code + else_if_code + ".Las_if_done_" + label + ":\n" + rest_after_else_if
                return code
            }
            if else_open >= block_end || __host_char_at(source, else_open) != "{" { return "" }
            int else_close = function_body_end(source, else_open + 1)
            if else_close < 0 || else_close > block_end { return "" }
            string else_code = asm_block_loop(source, else_open + 1, else_close, function_name, loop_start, loop_end)
            string rest_after_else = asm_block_loop(source, else_close + 1, block_end, function_name, loop_start, loop_end)
            string code = condition + "    cmp $1, %rax\n    je .Las_else_" + label + "\n"
            code = code + then_code + "    jmp .Las_if_done_" + label + "\n.Las_else_" + label + ":\n"
            code = code + else_code + ".Las_if_done_" + label + ":\n" + rest_after_else
            return code
        }
        string rest_after_if = asm_block_loop(source, close + 1, block_end, function_name, loop_start, loop_end)
        string code = condition + "    cmp $1, %rax\n    je .Las_if_done_" + label + "\n"
        code = code + then_code + ".Las_if_done_" + label + ":\n" + rest_after_if
        return code
    }
    if matches_at(source, index, "while") || matches_at(source, index, "for") {
        int keyword_size = 5
        if matches_at(source, index, "for") { keyword_size = 3 }
        int condition_start = skip_space(source, index + keyword_size)
        int open = condition_start
        int depth = 0
        for open < block_end {
            string ch = __host_char_at(source, open)
            if ch == "\"" {
                open = skip_quoted(source, open, block_end)
                continue
            }
            if ch == "(" { depth = depth + 1 }
            if ch == ")" { depth = depth - 1 }
            if ch == "{" && depth == 0 { break }
            open = open + 1
        }
        if open >= block_end { return "" }
        int close = function_body_end(source, open + 1)
        if close < 0 || close > block_end { return "" }
        string condition = asm_expression(source, condition_start, open, function_name)
        if condition == "" { return "" }
        string label = int_text(index)
        string start_label = ".Las_loop_start_" + label
        string end_label = ".Las_loop_end_" + label
        string body_code = asm_block_loop(source, open + 1, close, function_name, start_label, end_label)
        string rest_after_loop = asm_block_loop(source, close + 1, block_end, function_name, loop_start, loop_end)
        string code = start_label + ":\n" + condition + "    cmp $1, %rax\n    je " + end_label + "\n"
        code = code + body_code + "    jmp " + start_label + "\n" + end_label + ":\n" + rest_after_loop
        return code
    }
    int type_end = skip_identifier(source, index)
    if type_end == index { return "" }
    string first = __host_slice(source, index, type_end)
    int name_at = index
    int name_end = type_end
    int assign = skip_space(source, name_end)
    bool typed = first == "int" || first == "string" || first == "bool"
    if typed {
        name_at = assign
        name_end = skip_identifier(source, name_at)
        assign = skip_space(source, name_end)
    }
    string name = __host_slice(source, name_at, name_end)
    bool declaration = assign + 1 < block_end && __host_char_at(source, assign) == ":" &&
        __host_char_at(source, assign + 1) == "="
    bool assignment = assign < block_end && __host_char_at(source, assign) == "=" &&
        (assign + 1 >= block_end || __host_char_at(source, assign + 1) != "=")
    if typed && !assignment {
        string default_value = "    mov $1, %rax\n"
        string default_store = asm_local_store(source, function_name, index, name)
        if default_store == "" { return "" }
        string code = default_value + default_store
        code = code + asm_block_loop(source, name_end, block_end, function_name, loop_start, loop_end)
        return code
    }
    if typed || declaration || assignment {
        int value_start = skip_space(source, assign + 1)
        if declaration { value_start = skip_space(source, assign + 2) }
        int value_end = expression_end(source, value_start)
        string value = asm_expression(source, value_start, value_end, function_name)
        string store = asm_local_store(source, function_name, index, name)
        if value_end < 0 || value_end > block_end || value == "" || store == "" { return "" }
        return value + store + asm_block_loop(source, value_end + 1, block_end, function_name, loop_start, loop_end)
    }
    int expression_finish = expression_end(source, index)
    string expression = asm_expression(source, index, expression_finish, function_name)
    if expression_finish < 0 || expression_finish > block_end || expression == "" { return "" }
    return expression + asm_block_loop(source, expression_finish + 1, block_end, function_name, loop_start, loop_end)
}

func asm_block(string source, int raw_start, int block_end, string function_name) string {
    return asm_block_loop(source, raw_start, block_end, function_name, "", "")
}

func asm_function(string source, string name) string {
    int body = function_body(source, name)
    if body < 0 {
        eprintln("compile: asm function body not found: " + name)
        return ""
    }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 {
        eprintln("compile: asm function body end not found: " + name)
        return ""
    }
    string code = ".global s_fn_" + name + "\n.type s_fn_" + name + ", @function\ns_fn_" + name
    code = code + ":\n    push %rbp\n    mov %rsp, %rbp\n    sub $4096, %rsp\n"
    int parameter = 0
    for parameter < 6 && function_parameter_at(source, name, parameter) != "" {
        string pop = asm_argument_pop(parameter)
        string register = "%rdi"
        if parameter == 1 { register = "%rsi" }
        if parameter == 2 { register = "%rdx" }
        if parameter == 3 { register = "%rcx" }
        if parameter == 4 { register = "%r8" }
        if parameter == 5 { register = "%r9" }
        code = code + "    mov " + register + ", " + signed_int_text(0 - ((parameter + 1) * 8)) + "(%rbp)\n"
        parameter = parameter + 1
    }
    string body_code = asm_block(source, body + 1, body_end, name)
    if body_code == "" {
        eprintln("compile: asm function block unsupported: " + name)
        return ""
    }
    code = code + body_code + "    mov $1, %rax\n.Las_return_" + name
    code = code + ":\n    leave\n    ret\n.size s_fn_" + name + ", .-s_fn_" + name + "\n\n"
    return code
}

func asm_literal_byte(string source, int index) int {
    if __host_char_at(source, index) != "\\" { return __host_byte_at(source, index) }
    string escaped = __host_char_at(source, index + 1)
    if escaped == "n" { return 10 }
    if escaped == "r" { return 13 }
    if escaped == "t" { return 9 }
    return __host_byte_at(source, index + 1)
}

func asm_literals(string source) string {
    string output = ".balign 1\n.Las_literals:\n    .byte 0\n"
    int index = 0
    for index < len(source) {
        if __host_char_at(source, index) != "\"" { index = index + 1; continue }
        int start = index
        int cursor = index + 1
        int count = 0
        string bytes = ""
        for cursor < len(source) {
            string ch = __host_char_at(source, cursor)
            if ch == "\"" { break }
            bytes = bytes + int_text(asm_literal_byte(source, cursor)) + ","
            count = count + 1
            if ch == "\\" { cursor = cursor + 2 } else { cursor = cursor + 1 }
        }
        if cursor >= len(source) { return "" }
        output = output + ".balign 8\n.Las_string_" + int_text(start)
        output = output + ":\n    .quad 2\n    .quad " + int_text(count) + "\n    .byte " + bytes + "0\n"
        index = cursor + 1
    }
    return output
}

func emit_native_assembly(string source) string {
    string output = ".section .text\n.global s_main\n.type s_main, @function\ns_main:\n    jmp s_fn_main\n.size s_main, .-s_main\n\n"
    int index = 0
    int emitted = 0
    for index < len(source) {
        int declaration = find_function_from(source, index)
        if declaration < 0 { break }
        int name_at = skip_space(source, declaration + 4)
        int name_end = skip_identifier(source, name_at)
        string name = __host_slice(source, name_at, name_end)
        if name == "host_args" || name == "__host_read_to_string" || name == "__host_write_text_file" ||
            name == "__host_char_at" || name == "__host_byte_at" || name == "__host_byte_string" ||
            name == "__host_make_executable" || name == "__host_slice" {
            index = name_end
            continue
        }
        string function_code = asm_function(source, name)
        if function_code != "" {
            output = output + function_code
            emitted = emitted + 1
        } else if function_body(source, name) >= 0 {
            eprintln("compile: assembly subset skipped function: " + name)
        }
        index = name_end
    }
    if emitted == 0 || function_declaration(source, "main") < 0 { return "" }
    string literals = asm_literals(source)
    if literals == "" { return "" }
    return output + ".section .rodata\n" + literals + ".section .note.GNU-stack,\"\",@progbits\n"
}

func compile_native_assembly(string source, string output_path) int {
    string assembly = emit_native_assembly(source)
    if assembly == "" {
        eprintln("compile: source is outside implemented assembly bootstrap subset")
        return 1
    }
    if __host_write_text_file(output_path, assembly) != 0 {
        eprintln("compile: cannot write assembly output")
        return 1
    }
    return 0
}
