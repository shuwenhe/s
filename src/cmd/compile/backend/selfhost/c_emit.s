func c_bad(int position) string {
    return "S_C_UNSUPPORTED_" + int_text(position)
}

func c_arguments(string source, int start, int end, string function_name) string {
    int cursor = skip_trivia(source, start)
    string output = ""
    for cursor < end {
        int comma = argument_comma(source, cursor, end)
        int finish = end
        if comma >= 0 { finish = comma }
        string argument = c_expression(source, cursor, finish, function_name)
        if argument == "" { return c_bad(cursor) }
        if output != "" { output = output + "," }
        output = output + argument
        if comma < 0 { return output }
        cursor = skip_trivia(source, comma + 1)
    }
    return output
}

func c_expression(string source, int raw_start, int raw_end, string function_name) string {
    int start = skip_trivia(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return c_bad(start) }
    if __host_char_at(source, start) == "(" {
        int close = matching_paren(source, start, end)
        if close == end - 1 { return c_expression(source, start + 1, end - 1, function_name) }
    }
    int logical = logical_at(source, start, end, "||")
    if logical < 0 { logical = logical_at(source, start, end, "&&") }
    if logical >= 0 {
        string left = c_expression(source, start, logical, function_name)
        string right = c_expression(source, logical + 2, end, function_name)
        return "S_INT(S_TRUE(" + left + ")" + __host_slice(source, logical, logical + 2) + "S_TRUE(" + right + "))"
    }
    int compare = comparison_at(source, start, end)
    if compare >= 0 {
        int operator_end = compare + 1
        if __host_char_at(source, operator_end) == "=" { operator_end = operator_end + 1 }
        string left = c_expression(source, start, compare, function_name)
        string right = c_expression(source, operator_end, end, function_name)
        return "S_INT(s_cmp(" + left + "," + right + ")" + __host_slice(source, compare, operator_end) + "0)"
    }
    int arithmetic = arithmetic_operator_at(source, start, end, false)
    if arithmetic < 0 { arithmetic = arithmetic_operator_at(source, start, end, true) }
    if arithmetic >= 0 {
        string left = c_expression(source, start, arithmetic, function_name)
        string right = c_expression(source, arithmetic + 1, end, function_name)
        string op = __host_char_at(source, arithmetic)
        if op == "+" { return "s_add(" + left + "," + right + ")" }
        if op == "-" { return "s_sub(" + left + "," + right + ")" }
        if op == "*" { return "s_mul(" + left + "," + right + ")" }
        if op == "/" { return "s_div(" + left + "," + right + ")" }
        if op == "%" { return "s_mod(" + left + "," + right + ")" }
        return c_bad(arithmetic)
    }
    if __host_char_at(source, start) == "-" {
        return "s_sub(S_INT(0)," + c_expression(source, start + 1, end, function_name) + ")"
    }
    if __host_char_at(source, start) == "!" {
        return "S_INT(!S_TRUE(" + c_expression(source, start + 1, end, function_name) + "))"
    }
    if __host_char_at(source, start) == "\"" && skip_quoted(source, start, end) == end {
        return "((SV)&s_lit_" + int_text(start) + ")"
    }
    if skip_uint(source, start) == end { return "S_INT(" + int_text(parse_uint(source, start)) + ")" }
    int name_end = skip_identifier(source, start)
    if name_end == start { return c_bad(start) }
    string name = __host_slice(source, start, name_end)
    if name_end == end {
        if name == "true" { return "S_INT(1)" }
        if name == "false" { return "S_INT(0)" }
        return "v_" + name
    }
    int open = skip_space(source, name_end)
    if open < end && __host_char_at(source, open) == "[" {
        int close = matching_square(source, open, end)
        if close != end - 1 { return c_bad(open) }
        return "s_index(v_" + name + "," + c_expression(source, open + 1, close, function_name) + ")"
    }
    if open >= end || __host_char_at(source, open) != "(" { return c_bad(open) }
    int close = matching_paren(source, open, end)
    if close != end - 1 { return c_bad(close) }
    return "s_fn_" + name + "(" + c_arguments(source, open + 1, close, function_name) + ")"
}

func c_control_open(string source, int start, int end) int {
    int index = start
    int depth = 0
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\"" { index = skip_quoted(source, index, end); continue }
        if ch == "(" { depth = depth + 1 }
        if ch == ")" { depth = depth - 1 }
        if ch == "{" && depth == 0 { return index }
        index = index + 1
    }
    return -1
}

func c_block(string source, int raw_start, int end, string function_name) string {
    int index = skip_trivia(source, raw_start)
    string output = ""
    for index < end {
        if __host_char_at(source, index) == ";" { index = skip_trivia(source, index + 1); continue }
        if matches_at(source, index, "if") || matches_at(source, index, "for") || matches_at(source, index, "while") {
            int keyword_end = skip_identifier(source, index)
            string keyword = __host_slice(source, index, keyword_end)
            if keyword != "if" && keyword != "for" && keyword != "while" { return c_bad(index) }
            int open = c_control_open(source, keyword_end, end)
            if open < 0 { return c_bad(index) }
            int close = function_body_end(source, open + 1)
            if close < 0 || close >= end { return c_bad(index) }
            string condition = c_expression(source, keyword_end, open, function_name)
            string body_code = c_block(source, open + 1, close, function_name)
            if keyword == "for" { keyword = "while" }
            output = output + keyword + "(S_TRUE(" + condition + ")){\n" + body_code + "}\n"
            index = skip_trivia(source, close + 1)
            if index < end && matches_at(source, index, "else") {
                if keyword != "if" { return c_bad(index) }
                index = skip_trivia(source, index + 4)
                output = output + "else "
                if matches_at(source, index, "if") { continue }
                if __host_char_at(source, index) != "{" { return c_bad(index) }
                close = function_body_end(source, index + 1)
                if close < 0 || close >= end { return c_bad(index) }
                output = output + "{\n" + c_block(source, index + 1, close, function_name) + "}\n"
                index = skip_trivia(source, close + 1)
            }
            continue
        }
        int finish = expression_end(source, index)
        if finish < 0 || finish > end { return c_bad(index) }
        int word_end = skip_identifier(source, index)
        string first = __host_slice(source, index, word_end)
        if first == "return" {
            output = output + "return " + c_expression(source, word_end, finish, function_name) + ";\n"
        } else if first == "break" || first == "continue" {
            if trim_space_end(source, word_end, finish) != word_end { return c_bad(index) }
            output = output + first + ";\n"
        } else {
            int name_start = index
            int name_end = word_end
            bool declaration = first == "int" || first == "string" || first == "bool"
            if declaration { name_start = skip_space(source, word_end); name_end = skip_identifier(source, name_start) }
            int assign = skip_space(source, name_end)
            if matches_at(source, assign, ":=") { declaration = true }
            if __host_char_at(source, assign) == "=" || matches_at(source, assign, ":=") {
                int value_start = assign + 1
                if matches_at(source, assign, ":=") { value_start = assign + 2 }
                string prefix = ""
                if declaration { prefix = "SV " }
                output = output + prefix + "v_" + __host_slice(source, name_start, name_end) + " = "
                    + c_expression(source, value_start, finish, function_name) + ";\n"
            } else if declaration {
                output = output + "SV v_" + __host_slice(source, name_start, name_end) + " = S_INT(0);\n"
            } else {
                output = output + "(void)(" + c_expression(source, index, finish, function_name) + ");\n"
            }
        }
        index = skip_trivia(source, finish + 1)
    }
    return output
}

func c_signature(string source, string name) string {
    string output = "static SV s_fn_" + name + "("
    int index = 0
    for function_parameter_at(source, name, index) != "" {
        if index > 0 { output = output + "," }
        output = output + "SV v_" + function_parameter_at(source, name, index)
        index = index + 1
    }
    if index == 0 { output = output + "void" }
    return output + ")"
}

func emit_selfhost_c(string source) string {
    string output = "#include \"selfhost_portable.h\"\n"
    string signatures = ""
    string bodies = ""
    int index = 0
    for index < len(source) {
        index = skip_trivia(source, index)
        if __host_char_at(source, index) == "\"" {
            int end = skip_quoted(source, index, len(source))
            if end <= index || __host_char_at(source, end - 1) != "\"" { return c_bad(index) }
            string literal = __host_slice(source, index, end)
            output = output + "static SString s_lit_" + int_text(index) + " = {0,sizeof(" + literal + ")-1," + literal + ",0,0};\n"
            index = end
        } else { index = index + 1 }
    }
    index = 0
    for index < len(source) {
        int declaration = find_function_from(source, index)
        if declaration < 0 { break }
        int start = skip_space(source, declaration + 4)
        int end = skip_identifier(source, start)
        string name = __host_slice(source, start, end)
        int body = function_body(source, name)
        if body >= 0 {
            int close = function_body_end(source, body + 1)
            if close < 0 { return c_bad(body) }
            string signature = c_signature(source, name)
            signatures = signatures + signature + ";\n"
            bodies = bodies + signature + "{\n" + c_block(source, body + 1, close, name) + "return S_INT(0);\n}\n"
            index = close + 1
        } else { index = end }
    }
    return output + signatures + bodies + "int main(int argc,char **argv){s_init(argc,argv);SV result=s_fn_main();int status=(int)S_NUM(result);s_destroy();return status;}\n"
}

func compile_selfhost_c(string source, string path) int {
    string output = emit_selfhost_c(source)
    if find_word(output, "S_C_UNSUPPORTED") >= 0 { eprintln("compile: unsupported C bootstrap construct"); return 1 }
    if __host_write_text_file(path, output) != 0 { eprintln("compile: cannot write C output"); return 1 }
    return 0
}
