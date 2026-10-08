    int index = scope_start
    int value = -1
    for index < before {
        if matches_at(source, index, name) {
            bool left_boundary = index == 0 || !is_ident_continue(__host_char_at(source, index - 1))
            int after_name = index + len(name)
            bool right_boundary = after_name == len(source) || !is_ident_continue(__host_char_at(source, after_name))
            int assign = skip_space(source, after_name)
            if left_boundary && right_boundary && assign + 1 < before &&
                __host_char_at(source, assign) == ":" && __host_char_at(source, assign + 1) == "=" {
                int initializer = skip_space(source, assign + 2)
                int initializer_end = expression_end(source, initializer)
                if initializer_end < 0 || initializer_end >= before { return -1 }
                value = evaluate_expression(source, initializer, initializer_end, scope_start, parameter_name, parameter_value)
                if value < 0 { return -1 }
                index = initializer_end + 1
                continue
            }
        }
        index = index + 1
    }
    if value < 0 && parameter_name != "" && name == parameter_name { return parameter_value }
    return value
}

func resolve_function(string source, string name, bool has_argument, int argument) int {
    int body = function_body(source, name)
    if body < 0 { return -1 }
    string parameter = function_parameter(source, name)
    if parameter == "" && has_argument { return -1 }
    if parameter != "" && !has_argument { return -1 }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return -1 }
    return evaluate_block(source, body, body_end, body, parameter, argument)
}

func factor_value(string source, int start, int next, int scope_start, string parameter_name, int parameter_value) int {
    string ch = __host_char_at(source, start)
    if ch == "(" { return evaluate_expression(source, start + 1, next - 1, scope_start, parameter_name, parameter_value) }
    if is_digit(ch) { return parse_uint(source, start) }
    if is_alpha(ch) {
        int name_end = skip_identifier(source, start)
        string name = __host_slice(source, start, name_end)
        int after_name = skip_space(source, name_end)
        if after_name < next && __host_char_at(source, after_name) == "(" {
            int close = next - 1
            int argument_start = skip_space(source, after_name + 1)
            if argument_start == close { return resolve_function(source, name, false, 0) }
            int argument = evaluate_expression(source, argument_start, close, scope_start, parameter_name, parameter_value)
            if argument < 0 { return -1 }
            return resolve_function(source, name, true, argument)
        }
        return resolve_identifier(source, name, scope_start, start, parameter_name, parameter_value)
    }
    return -1
}

func compile_local_constant_value(string source, int scope_start, int before, string name) int {
    int index = scope_start
    int value = -1
    for index < before {
        int type_end = skip_identifier(source, index)
        if type_end > index {
            string type_name = __host_slice(source, index, type_end)
            if type_name == "int" || type_name == "string" || type_name == "bool" {
                int typed_name_at = skip_space(source, type_end)
                int typed_name_end = skip_identifier(source, typed_name_at)
                if typed_name_end > typed_name_at && __host_slice(source, typed_name_at, typed_name_end) == name {
                    bool typed_is_bool = type_name == "bool"
                    int typed_assign = skip_space(source, typed_name_end)
                    if typed_assign + 1 < before && __host_char_at(source, typed_assign) == ":" &&
                        __host_char_at(source, typed_assign + 1) == "=" {
                        int initializer = skip_space(source, typed_assign + 2)
                        int initializer_end = expression_end(source, initializer)
                        if initializer_end < 0 || initializer_end >= before { return -1 }
                        if typed_is_bool {
                            value = evaluate_expression(source, initializer, initializer_end, scope_start, "", 0)
                        } else {
                            value = evaluate_arithmetic_expression(source, initializer, initializer_end, scope_start, "", 0)
                        }
                        if value < 0 { return -1 }
                        index = initializer_end + 1
                        continue
                    }
                    if typed_assign < before && __host_char_at(source, typed_assign) == "=" &&
                        (typed_assign + 1 >= before || __host_char_at(source, typed_assign + 1) != "=") {
                        int initializer = skip_space(source, typed_assign + 1)
                        int initializer_end = expression_end(source, initializer)
                        if initializer_end < 0 || initializer_end >= before { return -1 }
                        if typed_is_bool {
                            value = evaluate_expression(source, initializer, initializer_end, scope_start, "", 0)
                        } else {
                            value = evaluate_arithmetic_expression(source, initializer, initializer_end, scope_start, "", 0)
                        }
                        if value < 0 { return -1 }
                        index = initializer_end + 1
                        continue
                    }
                }
            }
        }
        if matches_at(source, index, name) {
            bool left_boundary = index == 0 || !is_ident_continue(__host_char_at(source, index - 1))
            int after_name = index + len(name)
            bool right_boundary = after_name == len(source) || !is_ident_continue(__host_char_at(source, after_name))
            if left_boundary && right_boundary {
                int assign = skip_space(source, after_name)
                if assign + 1 < before && __host_char_at(source, assign) == ":" &&
                    __host_char_at(source, assign + 1) == "=" {
                    int initializer = skip_space(source, assign + 2)
                    int initializer_end = expression_end(source, initializer)
                    if initializer_end < 0 || initializer_end >= before { return -1 }
                    value = evaluate_arithmetic_expression(source, initializer, initializer_end, scope_start, "", 0)
                    if value < 0 { return -1 }
                    index = initializer_end + 1
                    continue
                }
                if assign < before && __host_char_at(source, assign) == "=" &&
                    (assign + 1 >= before || __host_char_at(source, assign + 1) != "=") {
                    int initializer = skip_space(source, assign + 1)
                    int initializer_end = expression_end(source, initializer)
                    if initializer_end < 0 || initializer_end >= before { return -1 }
                    value = evaluate_arithmetic_expression(source, initializer, initializer_end, scope_start, "", 0)
                    if value < 0 { return -1 }
                    index = initializer_end + 1
                    continue
                }
            }
        }
        index = index + 1
    }
    return value
}

func evaluate_arithmetic_expression(string source, int start, int end, int scope_start, string parameter_name, int parameter_value) int {
    int index = skip_space(source, start)
    int next = factor_end(source, index, end)
    if next < 0 { return -1 }
    int term = factor_value(source, index, next, scope_start, parameter_name, parameter_value)
    if term < 0 { return -1 }
    int total = 0
    string additive = "+"
    index = next
    for true {
        if index == end {
            if additive == "+" { return total + term }
            return total - term
        }
        index = skip_space(source, index)
        if index == end {
            if additive == "+" { return total + term }
            return total - term
        }
        if index > end { return -1 }
        string operator = __host_char_at(source, index)
        if operator != "+" && operator != "-" && operator != "*" && operator != "/" && operator != "%" { return -1 }
        int factor_start = skip_space(source, index + 1)
        next = factor_end(source, factor_start, end)
        if next < 0 { return -1 }
        int factor = factor_value(source, factor_start, next, scope_start, parameter_name, parameter_value)
        if factor < 0 { return -1 }
        if operator == "*" { term = term * factor }
        if operator == "/" {
            if factor == 0 { return -1 }
            term = term / factor
        }
        if operator == "%" {
            if factor == 0 { return -1 }
            term = term % factor
        }
        if operator == "+" || operator == "-" {
            if additive == "+" { total = total + term }
            if additive == "-" { total = total - term }
            additive = operator
            term = factor
        }
        index = next
    }
    return -1
}

func comparison_at(string source, int start, int end) int {
    int index = start
    int depth = 0
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\"" { index = skip_quoted(source, index, end); continue }
        if ch == "(" { depth = depth + 1 }
        if ch == ")" { depth = depth - 1 }
        if depth == 0 && (ch == "=" || ch == "!" || ch == "<" || ch == ">") {
            return index
        }
        index = index + 1
    }
    return -1
}

func logical_at(string source, int start, int end, string operator) int {
    int index = start
    int depth = 0
    for index + 1 < end {
        string ch = __host_char_at(source, index)
        if ch == "\"" { index = skip_quoted(source, index, end); continue }
        if ch == "(" { depth = depth + 1 }
        if ch == ")" { depth = depth - 1 }
        if depth == 0 && matches_at(source, index, operator) { return index }
        index = index + 1
    }
    return -1
}

func evaluate_expression(string source, int start, int end, int scope_start, string parameter_name, int parameter_value) int {
    int logical = logical_at(source, start, end, "||")
    if logical >= 0 {
        int left_logical = evaluate_expression(source, start, logical, scope_start, parameter_name, parameter_value)
        if left_logical < 0 { return -1 }
        if left_logical != 0 { return 1 }
        int right_logical = evaluate_expression(source, logical + 2, end, scope_start, parameter_name, parameter_value)
        if right_logical < 0 { return -1 }
        if right_logical != 0 { return 1 }
        return 0
    }
    logical = logical_at(source, start, end, "&&")
    if logical >= 0 {
        int left_logical = evaluate_expression(source, start, logical, scope_start, parameter_name, parameter_value)
        if left_logical < 0 { return -1 }
        if left_logical == 0 { return 0 }
        int right_logical = evaluate_expression(source, logical + 2, end, scope_start, parameter_name, parameter_value)
        if right_logical < 0 { return -1 }
        if right_logical != 0 { return 1 }
        return 0
    }
    int trimmed_start = skip_space(source, start)
    if trimmed_start < end && __host_char_at(source, trimmed_start) == "!" &&
        (trimmed_start + 1 >= end || __host_char_at(source, trimmed_start + 1) != "=") {
        int negated = evaluate_expression(source, trimmed_start + 1, end, scope_start, parameter_name, parameter_value)
        if negated < 0 { return -1 }
        if negated == 0 { return 1 }
        return 0
    }
    int compare = comparison_at(source, start, end)
    if compare < 0 {
        return evaluate_arithmetic_expression(source, start, end, scope_start, parameter_name, parameter_value)
    }
    int operator_end = compare + 1
    if operator_end < end && __host_char_at(source, operator_end) == "=" {
        operator_end = operator_end + 1
    }
    string operator = __host_slice(source, compare, operator_end)
    if operator == "=" || operator == "!" { return -1 }
    int left = evaluate_arithmetic_expression(source, start, compare, scope_start, parameter_name, parameter_value)
    int right = evaluate_arithmetic_expression(source, operator_end, end, scope_start, parameter_name, parameter_value)
    if left < 0 || right < 0 { return -1 }
    if operator == "==" {
        if left == right { return 1 }
        return 0
    }
    if operator == "!=" {
        if left != right { return 1 }
        return 0
    }
    if operator == "<" {
        if left < right { return 1 }
        return 0
    }
    if operator == "<=" {
        if left <= right { return 1 }
        return 0
    }
    if operator == ">" {
        if left > right { return 1 }
        return 0
    }
    if operator == ">=" {
        if left >= right { return 1 }
        return 0
    }
    return -1
}

func evaluate_block(string source, int block_start, int block_end, int scope_start, string parameter_name, int parameter_value) int {
    int index = block_start
    for index < block_end {
        index = skip_space(source, index)
        if index >= block_end { return -1 }
        if matches_at(source, index, "return") {
            int start = skip_space(source, index + 6)
            int end = expression_end(source, start)
            if end < 0 || end > block_end { return -1 }
            return evaluate_expression(source, start, end, scope_start, parameter_name, parameter_value)
        }
        if matches_at(source, index, "if") {
            int condition_start = skip_space(source, index + 2)
            int open = condition_start
            int paren_depth = 0
            for open < block_end {
                string ch = __host_char_at(source, open)
                if ch == "(" { paren_depth = paren_depth + 1 }
                if ch == ")" { paren_depth = paren_depth - 1 }
                if ch == "{" && paren_depth == 0 { break }
                open = open + 1
            }
            if open >= block_end { return -1 }
            int close = function_body_end(source, open + 1)
            if close < 0 || close > block_end { return -1 }
            int condition = evaluate_expression(source, condition_start, open, scope_start, parameter_name, parameter_value)
            if condition < 0 { return -1 }
            if condition != 0 {
                int selected = evaluate_block(source, open + 1, close, scope_start, parameter_name, parameter_value)
                if selected >= 0 { return selected }
            }
            int after = skip_space(source, close + 1)
            if after + 4 <= block_end && matches_at(source, after, "else") {
                int else_open = skip_space(source, after + 4)
                if else_open >= block_end || __host_char_at(source, else_open) != "{" { return -1 }
                int else_close = function_body_end(source, else_open + 1)
                if else_close < 0 || else_close > block_end { return -1 }
                if condition == 0 {
                    int selected = evaluate_block(source, else_open + 1, else_close, scope_start, parameter_name, parameter_value)
                    if selected >= 0 { return selected }
                }
                index = else_close + 1
                continue
            }
            index = close + 1
            continue
        }
        index = index + 1
    }
    return -1
}

func evaluate_main_expression(string source) int {
    int body = function_body(source, "main")
    if body < 0 { return -1 }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return -1 }
    return evaluate_block(source, body + 1, body_end, body + 1, "", 0)
}

func compile_main_expression(string source) string {
    int value = evaluate_main_expression(source)
    if value < 0 { return "" }
    return "SSEED-TARGET-V1\nFUNC_BEGIN|main|_|_\nRET|" + int_text(value) + "|_|_\nFUNC_END|main|_|_\n"
}

func little16(int input) string {
    int value = input
    return __host_byte_string(value % 256) + __host_byte_string((value / 256) % 256)
}

func little32(int input) string {
    int value = input
    return little16(value % 65536) + little16((value / 65536) % 65536)
}

func little32_signed(int input) string {
    int value = input
    if value < 0 { value = value + 4294967296 }
    return little32(value)
}

func little64(int input) string {
    int value = input
    return little32(value) + little32(0)
}

func machine_test_rax() string {
    return __host_byte_string(72) + __host_byte_string(133) + __host_byte_string(192)
}

func machine_jump_zero(int displacement) string {
    return __host_byte_string(15) + __host_byte_string(132) + little32_signed(displacement)
}

func machine_jump_not_zero(int displacement) string {
    return __host_byte_string(15) + __host_byte_string(133) + little32_signed(displacement)
}

func machine_jump(int displacement) string {
    return __host_byte_string(233) + little32_signed(displacement)
}

func continue_marker() string {
    return __host_byte_string(1) + __host_byte_string(2) + __host_byte_string(3) + __host_byte_string(4) + __host_byte_string(5)
}

func break_marker() string {
    return __host_byte_string(6) + __host_byte_string(7) + __host_byte_string(8) + __host_byte_string(9) + __host_byte_string(10)
}

func rewrite_loop_jumps(string body, int prefix_len, string continue_jump, string break_jump) string {
    string continue_tag = continue_marker()
    string break_tag = break_marker()
    int continue_len = len(continue_tag)
    int break_len = len(break_tag)
    string output = ""
    int index = 0
    for index < len(body) {
        if index + continue_len <= len(body) && __host_slice(body, index, index + continue_len) == continue_tag {
            output = output + continue_jump
            index = index + continue_len
            continue
        }
        if index + break_len <= len(body) && __host_slice(body, index, index + break_len) == break_tag {
            int break_displacement = len(body) - len(output)
            output = output + machine_jump(break_displacement)
            index = index + break_len
            continue
        }
        output = output + __host_char_at(body, index)
        index = index + 1
    }
    return output
}

func machine_while(string condition, string body) string {
    string test = machine_test_rax()
    string exit_jump = machine_jump_zero(len(body) + 5)
    int back = 0 - (len(condition) + len(test) + len(exit_jump) + len(body) + 5)
    string continue_jump = machine_jump(0 - (len(condition) + len(test) + len(exit_jump) + 5))
    string rewritten_body = rewrite_loop_jumps(body, len(condition) + len(test) + len(exit_jump), continue_jump, "")
    return condition + test + exit_jump + rewritten_body + machine_jump(back)
}

func zeroes(int count) string {
    string output = ""
    int i = 0
    for i < count {
        output = output + __host_byte_string(0)
        i = i + 1
    }
    return output
}

func emit_elf_image(string code) string {
    int image_base = 4194304
    int code_offset = 120
    int file_size = code_offset + len(code)
    string elf = __host_byte_string(127) + "ELF"
    elf = elf + __host_byte_string(2) + __host_byte_string(1) + __host_byte_string(1) + zeroes(9)
    elf = elf + little16(2) + little16(62) + little32(1)
    elf = elf + little64(image_base + code_offset) + little64(64) + little64(0)
    elf = elf + little32(0) + little16(64) + little16(56) + little16(1)
    elf = elf + little16(0) + little16(0) + little16(0)
    elf = elf + little32(1) + little32(5) + little64(0)
    elf = elf + little64(image_base) + little64(image_base)
    elf = elf + little64(file_size) + little64(file_size) + little64(4096)
    return elf + code
}

func exit_sequence() string {
    return __host_byte_string(72) + __host_byte_string(199) + __host_byte_string(192) + little32(60)
        + __host_byte_string(15) + __host_byte_string(5)
}

func emit_exit_elf(int exit_code) string {
    string code = __host_byte_string(72) + __host_byte_string(199) + __host_byte_string(199) + little32(exit_code)
    return emit_elf_image(code + exit_sequence())
}

