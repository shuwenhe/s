package compile.selfhost.compiler
extern "intrinsic" func host_args() string[];
extern "intrinsic" func __host_read_to_string(string path) string;
extern "intrinsic" func __host_write_text_file(string path, string contents) int;
extern "intrinsic" func __host_char_at(string text, int index) string;
extern "intrinsic" func __host_byte_at(string text, int index) int;
extern "intrinsic" func __host_byte_string(int value) string;
extern "intrinsic" func __host_make_executable(string path) int;
extern "intrinsic" func __host_slice(string text, int start, int end) string;

func digit_text(int value) string {
    if value == 0 { return "0" }
    if value == 1 { return "1" }
    if value == 2 { return "2" }
    if value == 3 { return "3" }
    if value == 4 { return "4" }
    if value == 5 { return "5" }
    if value == 6 { return "6" }
    if value == 7 { return "7" }
    if value == 8 { return "8" }
    return "9"
}

func int_text(int value) string {
    if value < 10 { return digit_text(value) }
    return int_text(value / 10) + digit_text(value % 10)
}

func signed_int_text(int value) string {
    if value < 0 { return "-" + int_text(0 - value) }
    return int_text(value)
}

func source_line_at(string source, int position) int {
    int line = 1
    int index = 0
    for index < position && index < len(source) {
        if __host_char_at(source, index) == "\n" { line = line + 1 }
        index = index + 1
    }
    return line
}

func unsupported_item(string source, int position, string phase, string construct, string detail) string {
    if position < 0 { return "" }
    return phase + "|" + int_text(source_line_at(source, position)) + "|" + construct + "|" + detail + "\n"
}

func second_function_at(string source) int {
    int first = find_function_from(source, 0)
    if first < 0 { return -1 }
    return find_function_from(source, first + 4)
}

func first_stack_argument_function_at(string source) int {
    int index = 0
    for index < len(source) {
        int declaration = find_function_from(source, index)
        if declaration < 0 { return -1 }
        int name_at = skip_space(source, declaration + 4)
        int name_end = skip_identifier(source, name_at)
        if name_end == name_at { return -1 }
        string name = __host_slice(source, name_at, name_end)
        if function_parameter_abi_words(source, name) > 6 { return declaration }
        index = name_end
    }
    return -1
}

func find_code_word_from(string source, string word, int start) int {
    int index = start
    for index + len(word) <= len(source) {
        string ch = __host_char_at(source, index)
        if ch == "\"" {
            index = index + 1
            for index < len(source) {
                string quoted = __host_char_at(source, index)
                if quoted == "\\" { index = index + 2; continue }
                index = index + 1
                if quoted == "\"" { break }
            }
            continue
        }
        if ch == "/" && index + 1 < len(source) && __host_char_at(source, index + 1) == "/" {
            index = index + 2
            for index < len(source) && __host_char_at(source, index) != "\n" { index = index + 1 }
            continue
        }
        if ch == "/" && index + 1 < len(source) && __host_char_at(source, index + 1) == "*" {
            index = index + 2
            for index + 1 < len(source) &&
                !(__host_char_at(source, index) == "*" && __host_char_at(source, index + 1) == "/") {
                index = index + 1
            }
            if index + 1 < len(source) { index = index + 2 }
            continue
        }
        bool left_boundary = index == 0 || !is_ident_continue(__host_char_at(source, index - 1))
        bool right_boundary = index + len(word) == len(source) || !is_ident_continue(__host_char_at(source, index + len(word)))
        if left_boundary && right_boundary && matches_at(source, index, word) { return index }
        index = index + 1
    }
    return -1
}

func find_code_word(string source, string word) int {
    return find_code_word_from(source, word, 0)
}

func unsupported_report(string source) string {
    string report = "S-BOOTSTRAP-UNSUPPORTED-V1\n"
    report = report + "phase|line|construct|detail\n"

    int for_at = find_code_word(source, "for")
    if for_at >= 0 {
        report = report + unsupported_item(source, for_at, "semantic", "for-loop",
            "full Go-style for clauses are not lowered by the bootstrap backend")
    }
    int stack_at = first_stack_argument_function_at(source)
    if stack_at >= 0 {
        report = report + unsupported_item(source, stack_at, "codegen", "stack-arguments",
            "native bootstrap ABI currently supports at most six machine-word arguments")
    }
    return report
}

func parse_package_name(string source) string {
    int start = skip_trivia(source, 0)
    if !matches_at(source, start, "package") { return "" }
    int cursor = start + 7
    if cursor < len(source) && is_ident_continue(__host_char_at(source, cursor)) { return "" }
    cursor = skip_space(source, cursor)
    int name_start = cursor
    int segment_end = skip_identifier(source, cursor)
    if segment_end == cursor { return "" }
    cursor = segment_end
    for cursor < len(source) && __host_char_at(source, cursor) == "." {
        cursor = cursor + 1
        segment_end = skip_identifier(source, cursor)
        if segment_end == cursor { return "" }
        cursor = segment_end
    }
    if cursor < len(source) && !is_space(__host_char_at(source, cursor)) { return "" }
    return __host_slice(source, name_start, cursor)
}

func intrinsic_declaration_count(string source) int {
    int count = 0
    int cursor = 0
    for cursor < len(source) {
        int declaration = find_code_word_from(source, "extern", cursor)
        if declaration < 0 { return count }
        int index = skip_space(source, declaration + 6)
        if !matches_at(source, index, "\"intrinsic\"") { return -1 }
        index = skip_space(source, index + 11)
        if !matches_at(source, index, "func") { return -1 }
        index = skip_space(source, index + 4)
        int name_end = skip_identifier(source, index)
        if name_end == index { return -1 }
        index = skip_space(source, name_end)
        if index >= len(source) || __host_char_at(source, index) != "(" { return -1 }
        int close = matching_paren(source, index, len(source))
        if close < 0 { return -1 }
        index = skip_space(source, close + 1)
        if index >= len(source) || __host_char_at(source, index) == ";" { return -1 }
        for index < len(source) && __host_char_at(source, index) != ";" && __host_char_at(source, index) != "{" {
            index = index + 1
        }
        if index >= len(source) || __host_char_at(source, index) != ";" { return -1 }
        count = count + 1
        cursor = index + 1
    }
    return count
}

func known_intrinsic_id(string name) int {
    if name == "__host_byte_at" { return 1 }
    if name == "__host_slice" { return 2 }
    if name == "string_len" { return 3 }
    if name == "__host_byte_string" { return 4 }
    return 0
}

func resolve_intrinsic_id(string source, string name) int {
    int wanted = known_intrinsic_id(name)
    if wanted == 0 { return 0 }
    string declaration = "extern \"intrinsic\" func " + name
    int index = 0
    for index + len(declaration) <= len(source) {
        if matches_at(source, index, declaration) {
            int after = index + len(declaration)
            if after < len(source) && __host_char_at(source, after) == "(" { return wanted }
        }
        index = index + 1
    }
    return 0
}

func emit_intrinsic_machine(int intrinsic_id) string {
    if intrinsic_id == 1 {
        return __host_byte_string(49) + __host_byte_string(192)
            + __host_byte_string(72) + __host_byte_string(57) + __host_byte_string(242)
            + __host_byte_string(115) + __host_byte_string(4)
            + __host_byte_string(15) + __host_byte_string(182) + __host_byte_string(4) + __host_byte_string(23)
    }
    if intrinsic_id == 2 {
        return __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(248)
            + __host_byte_string(72) + __host_byte_string(1) + __host_byte_string(208)
            + __host_byte_string(72) + __host_byte_string(41) + __host_byte_string(209)
            + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(202)
    }
    if intrinsic_id == 3 {
        return __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(240)
    }
    if intrinsic_id == 4 {
        return __host_byte_string(72) + __host_byte_string(141) + __host_byte_string(133)
            + little32_signed(-248)
            + __host_byte_string(64) + __host_byte_string(136) + __host_byte_string(56)
            + __host_byte_string(186) + little32(1)
    }
    return ""
}

func is_space(string ch) bool {
    return ch == " " || ch == "\t" || ch == "\r" || ch == "\n"
}

func is_digit(string ch) bool {
    return ch >= "0" && ch <= "9"
}

func is_alpha(string ch) bool {
    return (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch == "_"
}

func is_ident_continue(string ch) bool {
    return is_alpha(ch) || is_digit(ch)
}

func skip_space(string source, int start) int {
    int index = start
    for index < len(source) && is_space(__host_char_at(source, index)) {
        index = index + 1
    }
    return index
}

func skip_trivia(string source, int start) int {
    int index = start
    for index < len(source) {
        index = skip_space(source, index)
        if index + 1 < len(source) && __host_char_at(source, index) == "/" &&
            __host_char_at(source, index + 1) == "/" {
            index = index + 2
            for index < len(source) && __host_char_at(source, index) != "\n" {
                index = index + 1
            }
            continue
        }
        if index + 1 < len(source) && __host_char_at(source, index) == "/" &&
            __host_char_at(source, index + 1) == "*" {
            index = index + 2
            for index + 1 < len(source) &&
                !(__host_char_at(source, index) == "*" && __host_char_at(source, index + 1) == "/") {
                index = index + 1
            }
            if index + 1 < len(source) { index = index + 2 }
            continue
        }
        return index
    }
    return index
}

func matches_at(string source, int index, string needle) bool {
    if index + len(needle) > len(source) { return false }
    int i = 0
    for i < len(needle) {
        if __host_char_at(source, index + i) != __host_char_at(needle, i) {
            return false
        }
        i = i + 1
    }
    return true
}

func find_word(string source, string word) int {
    int i = 0
    for i + len(word) <= len(source) {
        bool left_boundary = i == 0 || !is_ident_continue(__host_char_at(source, i - 1))
        bool right_boundary = i + len(word) == len(source) || !is_ident_continue(__host_char_at(source, i + len(word)))
        if left_boundary && right_boundary && matches_at(source, i, word) { return i }
        i = i + 1
    }
    return -1
}

func find_word_from(string source, string word, int start) int {
    int index = start
    for index + len(word) <= len(source) {
        bool left_boundary = index == 0 || !is_ident_continue(__host_char_at(source, index - 1))
        bool right_boundary = index + len(word) == len(source) || !is_ident_continue(__host_char_at(source, index + len(word)))
        if left_boundary && right_boundary && matches_at(source, index, word) { return index }
        index = index + 1
    }
    return -1
}

func find_function_from(string source, int start) int {
    int index = start
    int mode = 0
    int budget = len(source) * 4 + 64
    for index < len(source) && budget > 0 {
        budget = budget - 1
        string ch = __host_char_at(source, index)
        if mode == 1 {
            if ch == "\\" && index + 1 < len(source) {
                index = index + 2
            } else {
                if ch == "\"" { mode = 0 }
                index = index + 1
            }
        } else if mode == 2 {
            if ch == "\n" { mode = 0 }
            index = index + 1
        } else if mode == 3 {
            if ch == "*" && index + 1 < len(source) && __host_char_at(source, index + 1) == "/" {
                mode = 0
                index = index + 2
            } else {
                index = index + 1
            }
        } else if ch == "\"" {
            mode = 1
            index = index + 1
        } else if ch == "/" && index + 1 < len(source) && __host_char_at(source, index + 1) == "/" {
            mode = 2
            index = index + 2
        } else if ch == "/" && index + 1 < len(source) && __host_char_at(source, index + 1) == "*" {
            mode = 3
            index = index + 2
        } else {
            if matches_at(source, index, "func") {
                bool left_boundary = index == 0 || !is_ident_continue(__host_char_at(source, index - 1))
                bool right_boundary = index + 4 == len(source) ||
                    !is_ident_continue(__host_char_at(source, index + 4))
                if left_boundary && right_boundary { return index }
            }
            index = index + 1
        }
    }
    return -1
}

func function_declaration(string source, string name) int {
    int index = 0
    for index < len(source) {
        int function_at = find_function_from(source, index)
        if function_at < 0 { return -1 }
        int name_at = skip_space(source, function_at + 4)
        int name_end = skip_identifier(source, name_at)
        if name_end > name_at && __host_slice(source, name_at, name_end) == name {
            return function_at
        }
        index = function_at + 4
    }
    return -1
}

func function_body(string source, string name) int {
    int declaration = function_declaration(source, name)
    if declaration < 0 { return -1 }
    int scan = declaration + 4
    int budget = 1000000
    for scan < len(source) && budget > 0 && __host_char_at(source, scan) != "{" {
        budget = budget - 1
        if __host_char_at(source, scan) == ";" { return -1 }
        scan = scan + 1
    }
    if scan < len(source) { return scan }
    return -1
}

func function_parameter_at(string source, string name, int wanted) string {
    int declaration = function_declaration(source, name)
    if declaration < 0 { return "" }
    int name_at = skip_space(source, declaration + 4)
    int name_end = skip_identifier(source, name_at)
    int open = skip_space(source, name_end)
    if open >= len(source) || __host_char_at(source, open) != "(" { return "" }
    int close = matching_paren(source, open, len(source))
    if close < 0 { return "" }
    int cursor = skip_space(source, open + 1)
    int ordinal = 0
    for cursor < close {
        int previous_cursor = cursor
        int type_end = skip_identifier(source, cursor)
        if type_end == cursor { return "" }
        int parameter_at = skip_space(source, type_end)
        int parameter_end = skip_identifier(source, parameter_at)
        if parameter_end == parameter_at { return "" }
        if ordinal == wanted { return __host_slice(source, parameter_at, parameter_end) }
        cursor = skip_space(source, parameter_end)
        if cursor >= close || __host_char_at(source, cursor) != "," { return "" }
        cursor = skip_space(source, cursor + 1)
        if cursor <= previous_cursor { return "" }
        ordinal = ordinal + 1
    }
    return ""
}

func function_parameter(string source, string name) string {
    return function_parameter_at(source, name, 0)
}

func function_parameter_index(string source, string name, string wanted) int {
    int declaration = function_declaration(source, name)
    if declaration < 0 { return -1 }
    int name_at = skip_space(source, declaration + 4)
    int name_end = skip_identifier(source, name_at)
    int open = skip_space(source, name_end)
    if open >= len(source) || __host_char_at(source, open) != "(" { return -1 }
    int close = matching_paren(source, open, len(source))
    if close < 0 { return -1 }
    int cursor = skip_space(source, open + 1)
    int ordinal = 0
    for cursor < close {
        int previous_cursor = cursor
        int type_end = skip_identifier(source, cursor)
        if type_end == cursor { return -1 }
        int parameter_at = skip_space(source, type_end)
        int parameter_end = skip_identifier(source, parameter_at)
        if parameter_end == parameter_at { return -1 }
        if __host_slice(source, parameter_at, parameter_end) == wanted { return ordinal }
        cursor = skip_space(source, parameter_end)
        if cursor >= close || __host_char_at(source, cursor) != "," { return -1 }
        cursor = skip_space(source, cursor + 1)
        if cursor <= previous_cursor { return -1 }
        ordinal = ordinal + 1
    }
    return -1
}

func function_parameter_type_kind_at(string source, string name, int wanted) int {
    int declaration = function_declaration(source, name)
    if declaration < 0 { return -1 }
    int name_at = skip_space(source, declaration + 4)
    int name_end = skip_identifier(source, name_at)
    int open = skip_space(source, name_end)
    if open >= len(source) || __host_char_at(source, open) != "(" { return -1 }
    int close = matching_paren(source, open, len(source))
    if close < 0 { return -1 }
    int cursor = skip_space(source, open + 1)
    int ordinal = 0
    for cursor < close {
        int previous_cursor = cursor
        int type_end = skip_identifier(source, cursor)
        if type_end == cursor { return -1 }
        int kind = parse_type_kind(__host_slice(source, cursor, type_end))
        int parameter_at = skip_space(source, type_end)
        int parameter_end = skip_identifier(source, parameter_at)
        if kind < 0 || parameter_end == parameter_at { return -1 }
        if ordinal == wanted { return kind }
        cursor = skip_space(source, parameter_end)
        if cursor >= close || __host_char_at(source, cursor) != "," { return -1 }
        cursor = skip_space(source, cursor + 1)
        if cursor <= previous_cursor { return -1 }
        ordinal = ordinal + 1
    }
    return -1
}

func parse_type_kind(string name) int {
    if name == "void" || name == "()" { return 0 }
    if name == "int" { return 1 }
    if name == "bool" { return 2 }
    if name == "string" { return 3 }
    if name == "pointer" { return 4 }
    if name == "slice" { return 5 }
    return -1
}

func type_abi_words(int kind) int {
    if kind == 3 || kind == 5 { return 2 }
    if kind >= 0 { return 1 }
    return 0
}

func function_parameter_abi_offset(string source, string name, int wanted) int {
    int ordinal = 0
    int offset = 0
    for ordinal < wanted {
        int kind = function_parameter_type_kind_at(source, name, ordinal)
        if kind < 0 { return -1 }
        offset = offset + type_abi_words(kind)
        ordinal = ordinal + 1
    }
    if function_parameter_type_kind_at(source, name, wanted) < 0 { return -1 }
    return offset
}

func function_parameter_abi_words(string source, string name) int {
    int ordinal = 0
    int words = 0
    for function_parameter_at(source, name, ordinal) != "" {
        int kind = function_parameter_type_kind_at(source, name, ordinal)
        if kind < 0 { return -1 }
        words = words + type_abi_words(kind)
        ordinal = ordinal + 1
    }
    return words
}

func function_return_type_kind(string source, string name) int {
    int declaration = function_declaration(source, name)
    if declaration < 0 { return -1 }
    int name_at = skip_space(source, declaration + 4)
    int name_end = skip_identifier(source, name_at)
    int open = skip_space(source, name_end)
    if open >= len(source) || __host_char_at(source, open) != "(" { return -1 }
    int close = matching_paren(source, open, len(source))
    if close < 0 { return -1 }
    int result_at = skip_space(source, close + 1)
    if result_at < len(source) && __host_char_at(source, result_at) == "{" { return 0 }
    int result_end = skip_identifier(source, result_at)
    if result_end == result_at { return -1 }
    return parse_type_kind(__host_slice(source, result_at, result_end))
}

func identifier_matches(string source, int start, int end, string wanted) bool {
    if end - start != len(wanted) { return false }
    int offset = 0
    for start + offset < end {
        if __host_byte_at(source, start + offset) != __host_byte_at(wanted, offset) {
            return false
        }
        offset = offset + 1
    }
    return true
}

func function_symbol_count(string source, string wanted) int {
    int count = 0
    int index = 0
    for index < len(source) {
        int declaration = find_function_from(source, index)
        if declaration < 0 { return count }
        int name_at = skip_space(source, declaration + 4)
        int name_end = skip_identifier(source, name_at)
        if name_end == name_at { return -1 }
        if identifier_matches(source, name_at, name_end, wanted) { count = count + 1 }
        index = name_end
    }
    return count
}

func validate_function_symbols(string source) bool {
    int index = 0
    int main_count = function_symbol_count(source, "main")
    if main_count != 1 {
        eprintln("symbol: program must define exactly one main, found " + signed_int_text(main_count))
        return false
    }
    for index < len(source) {
        int declaration = find_function_from(source, index)
        if declaration < 0 { return true }
        int name_at = skip_space(source, declaration + 4)
        int name_end = skip_identifier(source, name_at)
        if name_end == name_at { eprintln("symbol: missing function name"); return false }
        string name = __host_slice(source, name_at, name_end)
        if function_symbol_count(source, name) != 1 {
            eprintln("symbol: duplicate function " + name)
            return false
        }
        if function_return_type_kind(source, name) < 0 {
            eprintln("symbol: unsupported return type in " + name)
            return false
        }
        if function_parameter_abi_words(source, name) < 0 {
            eprintln("symbol: invalid parameter ABI in " + name)
            return false
        }
        index = name_end
    }
    return true
}

func function_body_end(string source, int body) int {
    if body < 1 || body >= len(source) { return -1 }
    int index = body
    int depth = 1
    int budget = 1000000
    for index < len(source) && budget > 0 {
        budget = budget - 1
        string ch = __host_char_at(source, index)
        if ch == "\"" { index = skip_quoted(source, index, len(source)); continue }
        if ch == "/" && index + 1 < len(source) && __host_char_at(source, index + 1) == "/" {
            index = index + 2
            for index < len(source) && __host_char_at(source, index) != "\n" { index = index + 1 }
            continue
        }
        if ch == "/" && index + 1 < len(source) && __host_char_at(source, index + 1) == "*" {
            index = index + 2
            for index + 1 < len(source) &&
                !(__host_char_at(source, index) == "*" && __host_char_at(source, index + 1) == "/") {
                index = index + 1
            }
            if index + 1 < len(source) { index = index + 2 }
            continue
        }
        if ch == "{" { depth = depth + 1 }
        if ch == "}" {
            depth = depth - 1
            if depth == 0 { return index }
        }
        index = index + 1
    }
    return -1
}

func parse_uint(string source, int start) int {
    int value = 0
    int index = start
    for index < len(source) && is_digit(__host_char_at(source, index)) {
        string ch = __host_char_at(source, index)
        if ch == "0" { value = value * 10 }
        if ch == "1" { value = value * 10 + 1 }
        if ch == "2" { value = value * 10 + 2 }
        if ch == "3" { value = value * 10 + 3 }
        if ch == "4" { value = value * 10 + 4 }
        if ch == "5" { value = value * 10 + 5 }
        if ch == "6" { value = value * 10 + 6 }
        if ch == "7" { value = value * 10 + 7 }
        if ch == "8" { value = value * 10 + 8 }
        if ch == "9" { value = value * 10 + 9 }
        index = index + 1
    }
    return value
}

func skip_uint(string source, int start) int {
    int index = start
    for index < len(source) && is_digit(__host_char_at(source, index)) {
        index = index + 1
    }
    return index
}

func skip_identifier(string source, int start) int {
    int index = start
    for index < len(source) && is_ident_continue(__host_char_at(source, index)) {
        index = index + 1
    }
    return index
}

func skip_quoted(string source, int start, int end) int {
    int index = start + 1
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\\" { index = index + 2; continue }
        index = index + 1
        if ch == "\"" { return index }
    }
    return end
}

func expression_end(string source, int start) int {
    int index = start
    int depth = 0
    for index < len(source) {
        string ch = __host_char_at(source, index)
        if ch == "\"" { index = skip_quoted(source, index, len(source)); continue }
        if ch == "(" { depth = depth + 1 }
        if ch == ")" {
            if depth == 0 { return index }
            depth = depth - 1
        }
        if depth == 0 && ch == "\n" {
            int previous = index - 1
            for previous >= start && is_space(__host_char_at(source, previous)) {
                previous = previous - 1
            }
            if previous >= start {
                string last = __host_char_at(source, previous)
                if last == "|" || last == "&" || last == "+" || last == "-" ||
                    last == "*" || last == "/" || last == "%" || last == "=" ||
                    last == "<" || last == ">" || last == "!" || last == "," {
                    index = index + 1
                    continue
                }
            }
            return index
        }
        if depth == 0 && (ch == ";" || ch == "}") { return index }
        index = index + 1
    }
    return -1
}

func matching_paren(string source, int start, int end) int {
    int index = start
    int depth = 0
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\"" { index = skip_quoted(source, index, end); continue }
        if ch == "(" { depth = depth + 1 }
        if ch == ")" {
            depth = depth - 1
            if depth == 0 { return index }
        }
        index = index + 1
    }
    return -1
}

func matching_square(string source, int start, int end) int {
    int depth = 0
    int index = start
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\"" { index = skip_quoted(source, index, end); continue }
        if ch == "[" { depth = depth + 1 }
        if ch == "]" {
            depth = depth - 1
            if depth == 0 { return index }
        }
        index = index + 1
    }
    return -1
}

func factor_end(string source, int start, int end) int {
    int index = skip_space(source, start)
    if index >= end { return -1 }
    string ch = __host_char_at(source, index)
    if is_digit(ch) { return skip_uint(source, index) }
    if is_alpha(ch) {
        int name_end = skip_identifier(source, index)
        int after_name = skip_space(source, name_end)
        if after_name < end && __host_char_at(source, after_name) == "(" {
            int close = matching_paren(source, after_name, end)
            if close < 0 { return -1 }
            return close + 1
        }
        return name_end
    }
    if ch == "(" {
        int close = matching_paren(source, index, end)
        if close < 0 { return -1 }
        return close + 1
    }
    return -1
}

func resolve_identifier(string source, string name, int scope_start, int before, string parameter_name, int parameter_value) int {
