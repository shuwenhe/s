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

func trim_space_end(string source, int start, int end) int {
    int result = end
    for result > start && is_space(__host_char_at(source, result - 1)) {
        result = result - 1
    }
    return result
}

func arithmetic_operator_at(string source, int start, int end, bool product) int {
    int index = start
    int depth = 0
    int result = -1
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\"" { index = skip_quoted(source, index, end); continue }
        if ch == "(" { depth = depth + 1 }
        if ch == ")" { depth = depth - 1 }
        if depth == 0 {
            if !product && (ch == "+" || ch == "-") && index > start { result = index }
            if product && (ch == "*" || ch == "/" || ch == "%") { result = index }
        }
        index = index + 1
    }
    return result
}

func arithmetic_machine_op(string operator) string {
    if operator == "+" {
        return __host_byte_string(72) + __host_byte_string(1) + __host_byte_string(200)
    }
    if operator == "-" {
        return __host_byte_string(72) + __host_byte_string(41) + __host_byte_string(200)
    }
    if operator == "*" {
        return __host_byte_string(72) + __host_byte_string(15) + __host_byte_string(175) + __host_byte_string(193)
    }
    string divide = __host_byte_string(72) + __host_byte_string(49) + __host_byte_string(210)
        + __host_byte_string(72) + __host_byte_string(247) + __host_byte_string(241)
    if operator == "%" {
        return divide + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(208)
    }
    return divide
}

func plain_uint_value(string source, int start, int end) int {
    int trimmed_start = skip_space(source, start)
    int trimmed_end = trim_space_end(source, trimmed_start, end)
    if trimmed_start >= trimmed_end { return -1 }
    if __host_char_at(source, trimmed_start) == "(" {
        int close = matching_paren(source, trimmed_start, trimmed_end)
        if close == trimmed_end - 1 {
            return plain_uint_value(source, trimmed_start + 1, trimmed_end - 1)
        }
    }
    int number_end = skip_uint(source, trimmed_start)
    if number_end != trimmed_end { return -1 }
    return parse_uint(source, trimmed_start)
}

func fold_binary_uint_value(int left, int right, string operator) int {
    if operator == "+" { return left + right }
    if operator == "-" { return left - right }
    if operator == "*" { return left * right }
    if operator == "/" {
        if right == 0 { return -1 }
        return left / right
    }
    if operator == "%" {
        if right == 0 { return -1 }
        return left % right
    }
    return -1
}

func simplify_binary_uint(string source, int start, int operator_at, int end) string {
    int left_trimmed = skip_space(source, start)
    int right_trimmed = skip_space(source, operator_at + 1)
    int left_end = trim_space_end(source, left_trimmed, operator_at)
    int right_end = trim_space_end(source, right_trimmed, end)
    if left_trimmed < left_end && left_end - left_trimmed == right_end - right_trimmed &&
        __host_slice(source, left_trimmed, left_end) == __host_slice(source, right_trimmed, right_end) {
        string operator = __host_char_at(source, operator_at)
        if operator == "+" { return __host_byte_string(72) + __host_byte_string(141) + __host_byte_string(4) + __host_byte_string(125) + little32(0) }
        if operator == "-" { return __host_byte_string(184) + little32(0) }
    }
    int left_value = plain_uint_value(source, start, operator_at)
    int right_value = plain_uint_value(source, operator_at + 1, end)
    string operator = __host_char_at(source, operator_at)
    if left_value >= 0 && right_value >= 0 {
        int folded = fold_binary_uint_value(left_value, right_value, operator)
        if folded >= 0 { return __host_byte_string(184) + little32(folded) }
    }
    if operator == "+" {
        if right_value == 0 { return emit_arithmetic_machine(source, start, operator_at) }
        if left_value == 0 { return emit_arithmetic_machine(source, operator_at + 1, end) }
    }
    if operator == "-" && right_value == 0 { return emit_arithmetic_machine(source, start, operator_at) }
    if operator == "*" {
        if left_value == 0 || right_value == 0 { return __host_byte_string(184) + little32(0) }
        if right_value == 1 { return emit_arithmetic_machine(source, start, operator_at) }
        if left_value == 1 { return emit_arithmetic_machine(source, operator_at + 1, end) }
    }
    if operator == "/" && right_value == 1 { return emit_arithmetic_machine(source, start, operator_at) }
    if operator == "%" && right_value == 1 { return __host_byte_string(184) + little32(0) }
    return ""
}

func machine_binary(string left, string right, string operator) string {
    if left == "" || right == "" { return "" }
    return left + __host_byte_string(80) + right
        + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(193)
        + __host_byte_string(88) + arithmetic_machine_op(operator)
}

func emit_arithmetic_machine(string source, int raw_start, int raw_end) string {
    int start = skip_space(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return "" }
    if __host_char_at(source, start) == "(" {
        int close = matching_paren(source, start, end)
        if close == end - 1 {
            return emit_arithmetic_machine(source, start + 1, end - 1)
        }
    }
    int operator_at = arithmetic_operator_at(source, start, end, false)
    if operator_at < 0 { operator_at = arithmetic_operator_at(source, start, end, true) }
    if operator_at >= 0 {
        string simplified = simplify_binary_uint(source, start, operator_at, end)
        if simplified != "" { return simplified }
        string left = emit_arithmetic_machine(source, start, operator_at)
        string right = emit_arithmetic_machine(source, operator_at + 1, end)
        return machine_binary(left, right, __host_char_at(source, operator_at))
    }
    int number_end = skip_uint(source, start)
    if number_end != end { return "" }
    return __host_byte_string(184) + little32(parse_uint(source, start))
}

func comparison_machine_op(string operator) string {
    if operator == "==" { return __host_byte_string(15) + __host_byte_string(148) + __host_byte_string(192) }
    if operator == "!=" { return __host_byte_string(15) + __host_byte_string(149) + __host_byte_string(192) }
    if operator == "<" { return __host_byte_string(15) + __host_byte_string(156) + __host_byte_string(192) }
    if operator == "<=" { return __host_byte_string(15) + __host_byte_string(158) + __host_byte_string(192) }
    if operator == ">" { return __host_byte_string(15) + __host_byte_string(159) + __host_byte_string(192) }
    return __host_byte_string(15) + __host_byte_string(157) + __host_byte_string(192)
}

func fold_compare_uint_value(int left, int right, string operator) int {
    if operator == "==" { if left == right { return 1 } return 0 }
    if operator == "!=" { if left != right { return 1 } return 0 }
    if operator == "<" { if left < right { return 1 } return 0 }
    if operator == "<=" { if left <= right { return 1 } return 0 }
    if operator == ">" { if left > right { return 1 } return 0 }
    if left >= right { return 1 }
    return 0
}

func fold_logical_uint_value(int left, int right, string operator) int {
    if operator == "||" {
        if left != 0 || right != 0 { return 1 }
        return 0
    }
    if left != 0 && right != 0 { return 1 }
    return 0
}

func simplify_logical_uint(string source, int start, int operator_at, int end) string {
    int left_value = plain_uint_value(source, start, operator_at)
    int right_value = plain_uint_value(source, operator_at + 2, end)
    string operator = __host_slice(source, operator_at, operator_at + 2)
    if left_value >= 0 && right_value >= 0 {
        int folded = fold_logical_uint_value(left_value, right_value, operator)
        return __host_byte_string(184) + little32(folded)
    }
    if operator == "||" {
        if left_value != 0 { return __host_byte_string(184) + little32(1) }
        if right_value != 0 { return __host_byte_string(184) + little32(1) }
    }
    if operator == "&&" {
        if left_value == 0 { return __host_byte_string(184) + little32(0) }
        if right_value == 0 { return __host_byte_string(184) + little32(0) }
    }
    return ""
}

func emit_multi_condition_constant(string source, int start, int end) int {
    int trimmed_start = skip_space(source, start)
    int trimmed_end = trim_space_end(source, trimmed_start, end)
    if trimmed_start >= trimmed_end { return -1 }
    int logical = logical_at(source, trimmed_start, trimmed_end, "||")
    if logical >= 0 {
        int left_value = emit_multi_condition_constant(source, trimmed_start, logical)
        if left_value < 0 { return -1 }
        if left_value != 0 { return 1 }
        int right_value = emit_multi_condition_constant(source, logical + 2, trimmed_end)
        if right_value < 0 { return -1 }
        if right_value != 0 { return 1 }
        return 0
    }
    logical = logical_at(source, trimmed_start, trimmed_end, "&&")
    if logical >= 0 {
        int left_value = emit_multi_condition_constant(source, trimmed_start, logical)
        if left_value < 0 { return -1 }
        if left_value == 0 { return 0 }
        int right_value = emit_multi_condition_constant(source, logical + 2, trimmed_end)
        if right_value < 0 { return -1 }
        if right_value != 0 { return 1 }
        return 0
    }
    if __host_char_at(source, trimmed_start) == "(" {
        int close = matching_paren(source, trimmed_start, trimmed_end)
        if close == trimmed_end - 1 {
            return emit_multi_condition_constant(source, trimmed_start + 1, trimmed_end - 1)
        }
    }
    if __host_char_at(source, trimmed_start) == "!" &&
        (trimmed_start + 1 >= trimmed_end || __host_char_at(source, trimmed_start + 1) != "=") {
        int negated = emit_multi_condition_constant(source, trimmed_start + 1, trimmed_end)
        if negated < 0 { return -1 }
        if negated == 0 { return 1 }
        return 0
    }
    int compare = comparison_at(source, trimmed_start, trimmed_end)
    if compare >= 0 {
        int operator_end = compare + 1
        if operator_end < trimmed_end && __host_char_at(source, operator_end) == "=" {
            operator_end = operator_end + 1
        }
        string operator = __host_slice(source, compare, operator_end)
        int left_value = plain_uint_value(source, trimmed_start, compare)
        int right_value = plain_uint_value(source, operator_end, trimmed_end)
        if left_value >= 0 && right_value >= 0 {
            return fold_compare_uint_value(left_value, right_value, operator)
        }
        return -1
    }
    int value = plain_uint_value(source, trimmed_start, trimmed_end)
    if value >= 0 {
        if value != 0 { return 1 }
        return 0
    }
    return -1
}

func machine_compare(string left, string right, string operator) string {
    if left == "" || right == "" { return "" }
    return left + __host_byte_string(80) + right
        + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(193)
        + __host_byte_string(88)
        + __host_byte_string(72) + __host_byte_string(57) + __host_byte_string(200)
        + comparison_machine_op(operator)
        + __host_byte_string(72) + __host_byte_string(15) + __host_byte_string(182) + __host_byte_string(192)
}

func emit_condition_machine(string source, int start, int end) string {
    int compare = comparison_at(source, start, end)
    if compare < 0 { return emit_arithmetic_machine(source, start, end) }
    int operator_end = compare + 1
    if operator_end < end && __host_char_at(source, operator_end) == "=" { operator_end = operator_end + 1 }
    string operator = __host_slice(source, compare, operator_end)
    int left_value = plain_uint_value(source, start, compare)
    int right_value = plain_uint_value(source, operator_end, end)
    if left_value >= 0 && right_value >= 0 {
        int folded = fold_compare_uint_value(left_value, right_value, operator)
        return __host_byte_string(184) + little32(folded)
    }
    string left = emit_arithmetic_machine(source, start, compare)
    string right = emit_arithmetic_machine(source, operator_end, end)
    return machine_compare(left, right, operator)
}

func emit_condition_constant(string source, int start, int end) int {
    int compare = comparison_at(source, start, end)
    if compare < 0 {
        int value = plain_uint_value(source, start, end)
        if value >= 0 {
            if value != 0 { return 1 }
            return 0
        }
        return -1
    }
    int operator_end = compare + 1
    if operator_end < end && __host_char_at(source, operator_end) == "=" { operator_end = operator_end + 1 }
    int left_value = plain_uint_value(source, start, compare)
    int right_value = plain_uint_value(source, operator_end, end)
    if left_value < 0 || right_value < 0 { return -1 }
    return fold_compare_uint_value(left_value, right_value, __host_slice(source, compare, operator_end))
}

func emit_native_return_machine(string source, int return_at, int block_end) string {
    int start = skip_space(source, return_at + 6)
    int end = expression_end(source, start)
    if end < 0 || end > block_end { return "" }
    string expression = emit_arithmetic_machine(source, start, end)
    if expression == "" { return "" }
    string move_result = __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(199)
    return expression + move_result + exit_sequence()
}

func emit_native_block_machine(string source, int block_start, int block_end) string {
    int index = skip_space(source, block_start)
    if index >= block_end { return "" }
    if matches_at(source, index, "return") {
        return emit_native_return_machine(source, index, block_end)
    }
    if !matches_at(source, index, "if") { return "" }
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
    if open >= block_end { return "" }
    int close = function_body_end(source, open + 1)
    if close < 0 || close > block_end { return "" }
    int after = skip_space(source, close + 1)
    if after + 4 > block_end || !matches_at(source, after, "else") { return "" }
    int else_open = skip_space(source, after + 4)
    if else_open >= block_end || __host_char_at(source, else_open) != "{" { return "" }
    int else_close = function_body_end(source, else_open + 1)
    if else_close < 0 || else_close > block_end { return "" }
    int condition_value = emit_condition_constant(source, condition_start, open)
    if condition_value == 1 {
        return emit_native_block_machine(source, open + 1, close)
    }
    if condition_value == 0 {
        return emit_native_block_machine(source, else_open + 1, else_close)
    }
    string condition = emit_condition_machine(source, condition_start, open)
    string then_code = emit_native_block_machine(source, open + 1, close)
    string else_code = emit_native_block_machine(source, else_open + 1, else_close)
    if condition == "" || then_code == "" || else_code == "" { return "" }
    string test_result = machine_test_rax()
    string jump_false = machine_jump_zero(len(then_code))
    return condition + test_result + jump_false + then_code + else_code
}

func emit_native_expression_elf(string source) string {
    int body = function_body(source, "main")
    if body < 0 { return "" }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return "" }
    int return_at = skip_space(source, body + 1)
    if return_at >= body_end || !matches_at(source, return_at, "return") { return "" }
    int start = skip_space(source, return_at + 6)
    int end = expression_end(source, start)
    if end < 0 || end > body_end { return "" }
    int after = end
    if after < body_end && __host_char_at(source, after) == ";" { after = after + 1 }
    after = skip_space(source, after)
    if after != body_end { return "" }
    string expression_code = emit_arithmetic_machine(source, start, end)
    if expression_code == "" { return "" }
    string move_result = __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(199)
    return emit_elf_image(expression_code + move_result + exit_sequence())
}

func emit_native_control_elf(string source) string {
    int body = function_body(source, "main")
    if body < 0 { return "" }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return "" }
    string code = emit_native_block_machine(source, body + 1, body_end)
    if code == "" { return "" }
    return emit_elf_image(code)
}

func local_slot(string source, int scope_start, int before, string wanted) int {
    int index = scope_start
    int slot = 0
    for index <= before && index < len(source) {
        index = skip_space(source, index)
        if index > before || index >= len(source) { return -1 }
        if is_alpha(__host_char_at(source, index)) {
            int name_end = skip_identifier(source, index)
            string name = __host_slice(source, index, name_end)
            int assign = skip_space(source, name_end)
            if name == "int" || name == "string" || name == "bool" {
                int typed_name_at = assign
                int typed_name_end = skip_identifier(source, typed_name_at)
                string typed_name = __host_slice(source, typed_name_at, typed_name_end)
                int typed_assign = skip_space(source, typed_name_end)
                if typed_name_end > typed_name_at && (typed_assign >= len(source) ||
                    __host_char_at(source, typed_assign) != "=") {
                    if typed_name == wanted { return slot }
                    slot = slot + type_abi_words(parse_type_kind(name))
                    index = typed_name_end
                    continue
                }
                if typed_name_end > typed_name_at && typed_assign < len(source) &&
                    __host_char_at(source, typed_assign) == "=" &&
                    (typed_assign + 1 >= len(source) || __host_char_at(source, typed_assign + 1) != "=") {
                    if typed_name == wanted { return slot }
                    slot = slot + type_abi_words(parse_type_kind(name))
                    int typed_initializer = skip_space(source, typed_assign + 1)
                    int typed_initializer_end = expression_end(source, typed_initializer)
                    if typed_initializer_end < 0 { return -1 }
                    index = typed_initializer_end + 1
                    continue
                }
            }
            if assign + 1 < len(source) && __host_char_at(source, assign) == ":" &&
                __host_char_at(source, assign + 1) == "=" {
                if name == wanted { return slot }
                slot = slot + 1
                int initializer = skip_space(source, assign + 2)
                int initializer_end = expression_end(source, initializer)
                if initializer_end < 0 { return -1 }
                index = initializer_end + 1
                continue
            }
            index = name_end
            continue
        }
        index = index + 1
    }
    return -1
}

func local_type_kind(string source, int scope_start, int before, string wanted) int {
    int index = scope_start
    for index <= before && index < len(source) {
        index = skip_space(source, index)
        if index > before || index >= len(source) { return -1 }
        int type_end = skip_identifier(source, index)
        if type_end == index { index = index + 1; continue }
        string type_name = __host_slice(source, index, type_end)
        int kind = parse_type_kind(type_name)
        if kind >= 0 {
            int name_at = skip_space(source, type_end)
            int name_end = skip_identifier(source, name_at)
            if name_end > name_at && __host_slice(source, name_at, name_end) == wanted { return kind }
        }
        index = type_end
    }
    return -1
}

func stack_load(int slot) string {
    int displacement = 256 - ((slot + 1) * 8)
    return __host_byte_string(72) + __host_byte_string(139) + __host_byte_string(69)
        + __host_byte_string(displacement)
}

func stack_store(int slot) string {
    int displacement = 256 - ((slot + 1) * 8)
    return __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(69)
        + __host_byte_string(displacement)
}

func stack_load_rdx(int slot) string {
    int displacement = 256 - ((slot + 1) * 8)
    return __host_byte_string(72) + __host_byte_string(139) + __host_byte_string(85)
        + __host_byte_string(displacement)
}

func stack_store_rdx(int slot) string {
    int displacement = 256 - ((slot + 1) * 8)
    return __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(85)
        + __host_byte_string(displacement)
}

func emit_scoped_arithmetic_machine(string source, int raw_start, int raw_end, int scope_start) string {
    int start = skip_space(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return "" }
    if __host_char_at(source, start) == "(" {
        int close = matching_paren(source, start, end)
        if close == end - 1 {
            return emit_scoped_arithmetic_machine(source, start + 1, end - 1, scope_start)
        }
    }
    int operator_at = arithmetic_operator_at(source, start, end, false)
    if operator_at < 0 { operator_at = arithmetic_operator_at(source, start, end, true) }
    if operator_at >= 0 {
        string left = emit_scoped_arithmetic_machine(source, start, operator_at, scope_start)
        string right = emit_scoped_arithmetic_machine(source, operator_at + 1, end, scope_start)
        return machine_binary(left, right, __host_char_at(source, operator_at))
    }
    int number_end = skip_uint(source, start)
    if number_end == end { return __host_byte_string(184) + little32(parse_uint(source, start)) }
    int name_end = skip_identifier(source, start)
    if name_end == end {
        string name = __host_slice(source, start, name_end)
        int constant = compile_local_constant_value(source, scope_start, start, name)
        if constant >= 0 { return __host_byte_string(184) + little32(constant) }
        int slot = local_slot(source, scope_start, start, name)
        if slot < 0 || slot >= 15 { return "" }
        return stack_load(slot)
    }
    return ""
}

func emit_scoped_condition_machine(string source, int start, int end, int scope_start) string {
    int compare = comparison_at(source, start, end)
    if compare < 0 { return emit_scoped_arithmetic_machine(source, start, end, scope_start) }
    int operator_end = compare + 1
    if operator_end < end && __host_char_at(source, operator_end) == "=" { operator_end = operator_end + 1 }
    string operator = __host_slice(source, compare, operator_end)
    string left = emit_scoped_arithmetic_machine(source, start, compare, scope_start)
    string right = emit_scoped_arithmetic_machine(source, operator_end, end, scope_start)
    return machine_compare(left, right, operator)
}

func emit_assignment_block_machine(string source, int block_start, int block_end, int scope_start) string {
    int index = block_start
    string code = ""
    for index < block_end {
        index = skip_space(source, index)
        if index >= block_end { return code }
        if !is_alpha(__host_char_at(source, index)) { return "" }
        int name_end = skip_identifier(source, index)
        string name = __host_slice(source, index, name_end)
        int assign = skip_space(source, name_end)
        if assign >= block_end || __host_char_at(source, assign) != "=" ||
            (assign + 1 < block_end && __host_char_at(source, assign + 1) == "=") { return "" }
        int expression_start = skip_space(source, assign + 1)
        int expression_finish = expression_end(source, expression_start)
        if expression_finish < 0 || expression_finish > block_end { return "" }
        int slot = local_slot(source, scope_start, index, name)
        string value = emit_scoped_arithmetic_machine(source, expression_start, expression_finish, scope_start)
        if slot < 0 || value == "" { return "" }
        code = code + value + stack_store(slot)
        index = expression_finish + 1
    }
    return code
}

func emit_native_loop_elf(string source) string {
    int body = function_body(source, "main")
    if body < 0 { return "" }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return "" }
    string prefix = __host_byte_string(85) + __host_byte_string(72) + __host_byte_string(137)
        + __host_byte_string(229) + __host_byte_string(72) + __host_byte_string(129)
        + __host_byte_string(236) + little32(128)
    int index = body + 1
    for true {
        index = skip_space(source, index)
        if index >= body_end { return "" }
        if matches_at(source, index, "while") { break }
        if !is_alpha(__host_char_at(source, index)) { return "" }
        int name_end = skip_identifier(source, index)
        int assign = skip_space(source, name_end)
        if assign + 1 >= body_end || __host_char_at(source, assign) != ":" ||
            __host_char_at(source, assign + 1) != "=" { return "" }
        int initializer = skip_space(source, assign + 2)
        int initializer_end = expression_end(source, initializer)
        if initializer_end < 0 || initializer_end > body_end { return "" }
        int slot = local_slot(source, body + 1, index, __host_slice(source, index, name_end))
        string value = emit_scoped_arithmetic_machine(source, initializer, initializer_end, body + 1)
        if slot < 0 || value == "" { return "" }
        prefix = prefix + value + stack_store(slot)
        index = initializer_end + 1
    }
    int condition_start = skip_space(source, index + 5)
    int open = condition_start
    for open < body_end && __host_char_at(source, open) != "{" { open = open + 1 }
    if open >= body_end { return "" }
    int close = function_body_end(source, open + 1)
    if close < 0 || close > body_end { return "" }
    string condition = emit_scoped_condition_machine(source, condition_start, open, body + 1)
    string loop_body = emit_assignment_block_machine(source, open + 1, close, body + 1)
    if condition == "" || loop_body == "" { return "" }
    int return_at = find_word_from(source, "return", close + 1)
    if return_at < 0 || return_at >= body_end { return "" }
    int return_start = skip_space(source, return_at + 6)
    int return_end = expression_end(source, return_start)
    if return_end < 0 || return_end > body_end { return "" }
    string result = emit_scoped_arithmetic_machine(source, return_start, return_end, body + 1)
    if result == "" { return "" }
    string move_result = __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(199)
    return emit_elf_image(prefix + machine_while(condition, loop_body)
        + result + move_result + exit_sequence())
}

func decode_bootstrap_string(string source, int start, int end) string {
    string output = ""
    int index = start
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\\" && index + 1 < end {
            string escaped = __host_char_at(source, index + 1)
            if escaped == "n" { output = output + "\n" }
            if escaped == "r" { output = output + "\r" }
            if escaped == "t" { output = output + "\t" }
            if escaped == "\\" { output = output + "\\" }
            if escaped == "\"" { output = output + "\"" }
            index = index + 2
            continue
        }
        output = output + ch
        index = index + 1
    }
    return output
}

func emit_write_sequence(int address, int count) string {
    return __host_byte_string(72) + __host_byte_string(199) + __host_byte_string(192) + little32(1)
        + __host_byte_string(72) + __host_byte_string(199) + __host_byte_string(199) + little32(1)
        + __host_byte_string(72) + __host_byte_string(190) + little64(address)
        + __host_byte_string(72) + __host_byte_string(199) + __host_byte_string(194) + little32(count)
        + __host_byte_string(15) + __host_byte_string(5)
}

func emit_native_string_elf(string source) string {
    int body = function_body(source, "main")
    if body < 0 { return "" }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return "" }
    int print_at = find_word_from(source, "println", body + 1)
    if print_at < 0 || print_at >= body_end || print_at != skip_space(source, body + 1) { return "" }
    int open = skip_space(source, print_at + 7)
    if open >= body_end || __host_char_at(source, open) != "(" { return "" }
    int quote = skip_space(source, open + 1)
    if quote >= body_end || __host_char_at(source, quote) != "\"" { return "" }
    int string_end = quote + 1
    for string_end < body_end {
        if __host_char_at(source, string_end) == "\\" { string_end = string_end + 2; continue }
        if __host_char_at(source, string_end) == "\"" { break }
        string_end = string_end + 1
    }
    if string_end >= body_end { return "" }
    string literal = decode_bootstrap_string(source, quote + 1, string_end)
    int return_at = find_word_from(source, "return", string_end + 1)
    if return_at < 0 || return_at >= body_end { return "" }
    int return_start = skip_space(source, return_at + 6)
    int return_end = expression_end(source, return_start)
    if return_end < 0 || return_end > body_end { return "" }
    int after_return = return_end
    if after_return < body_end && __host_char_at(source, after_return) == ";" { after_return = after_return + 1 }
    after_return = skip_space(source, after_return)
    if after_return != body_end { return "" }
    string result = emit_arithmetic_machine(source, return_start, return_end)
    if result == "" { return "" }
    string move_result = __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(199)
    string tail = result + move_result + exit_sequence()
    string placeholder_write = emit_write_sequence(0, len(literal))
    int string_address = 4194304 + 120 + len(placeholder_write) + len(tail)
    string code = emit_write_sequence(string_address, len(literal)) + tail
    return emit_elf_image(code + literal)
}

func emit_array_expression_machine(string source, int raw_start, int raw_end, string array_name, int array_length) string {
    int start = skip_space(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return "" }
    if __host_char_at(source, start) == "(" {
        int close = matching_paren(source, start, end)
        if close == end - 1 {
            return emit_array_expression_machine(source, start + 1, end - 1, array_name, array_length)
        }
    }
    int operator_at = arithmetic_operator_at(source, start, end, false)
    if operator_at < 0 { operator_at = arithmetic_operator_at(source, start, end, true) }
    if operator_at >= 0 {
        string left = emit_array_expression_machine(source, start, operator_at, array_name, array_length)
        string right = emit_array_expression_machine(source, operator_at + 1, end, array_name, array_length)
        return machine_binary(left, right, __host_char_at(source, operator_at))
    }
    int number_end = skip_uint(source, start)
    if number_end == end { return __host_byte_string(184) + little32(parse_uint(source, start)) }
    int name_end = skip_identifier(source, start)
    if name_end <= start || __host_slice(source, start, name_end) != array_name { return "" }
    int open = skip_space(source, name_end)
    if open >= end || __host_char_at(source, open) != "[" { return "" }
    int index_start = skip_space(source, open + 1)
    int index_end = skip_uint(source, index_start)
    int close = skip_space(source, index_end)
    if close >= end || close != end - 1 || __host_char_at(source, close) != "]" { return "" }
    int element = parse_uint(source, index_start)
    if element < 0 || element >= array_length { return "" }
    return stack_load(element)
}

func emit_native_array_elf(string source) string {
    int body = function_body(source, "main")
    if body < 0 { return "" }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return "" }
    int declaration = skip_space(source, body + 1)
    if declaration >= body_end || !is_alpha(__host_char_at(source, declaration)) { return "" }
    int name_end = skip_identifier(source, declaration)
    string name = __host_slice(source, declaration, name_end)
    int assign = skip_space(source, name_end)
    if assign + 1 >= body_end || __host_char_at(source, assign) != ":" ||
        __host_char_at(source, assign + 1) != "=" { return "" }
    int open = skip_space(source, assign + 2)
    if open >= body_end || __host_char_at(source, open) != "[" { return "" }
    string code = __host_byte_string(85) + __host_byte_string(72) + __host_byte_string(137)
        + __host_byte_string(229) + __host_byte_string(72) + __host_byte_string(129)
        + __host_byte_string(236) + little32(128)
    int cursor = skip_space(source, open + 1)
    int count = 0
    for cursor < body_end && __host_char_at(source, cursor) != "]" {
        int value_end = skip_uint(source, cursor)
        if value_end == cursor || count >= 15 { return "" }
        code = code + __host_byte_string(184) + little32(parse_uint(source, cursor)) + stack_store(count)
        count = count + 1
        cursor = skip_space(source, value_end)
        if cursor < body_end && __host_char_at(source, cursor) == "," {
            cursor = skip_space(source, cursor + 1)
        } else if cursor < body_end && __host_char_at(source, cursor) != "]" {
            return ""
        }
    }
    if cursor >= body_end || __host_char_at(source, cursor) != "]" || count == 0 { return "" }
    int return_at = find_word_from(source, "return", cursor + 1)
    if return_at < 0 || return_at >= body_end { return "" }
    int return_start = skip_space(source, return_at + 6)
    int return_end = expression_end(source, return_start)
    if return_end < 0 || return_end > body_end { return "" }
    string result = emit_array_expression_machine(source, return_start, return_end, name, count)
    if result == "" { return "" }
    string move_result = __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(199)
    return emit_elf_image(code + result + move_result + exit_sequence())
}

func native_function_slot(string source, string wanted) int {
    if wanted == "main" { return 0 }
    int index = 0
    int slot = 1
    for index < len(source) {
        int declaration = find_function_from(source, index)
        if declaration < 0 { return -1 }
        int name_at = skip_space(source, declaration + 4)
        int name_end = skip_identifier(source, name_at)
        if name_end == name_at { return -1 }
        string name = __host_slice(source, name_at, name_end)
        if name != "main" && function_body(source, name) >= 0 {
            if name == wanted { return slot }
            slot = slot + 1
        }
        index = name_end
    }
    return -1
}

func native_function_stride() int {
    return 16384
}

func native_function_count(string source) int {
    int count = 1
    int index = 0
    for index < len(source) {
        int declaration = find_function_from(source, index)
        if declaration < 0 { return count }
        int name_at = skip_space(source, declaration + 4)
        int name_end = skip_identifier(source, name_at)
        if name_end == name_at { return -1 }
        string name = __host_slice(source, name_at, name_end)
        if name != "main" && function_body(source, name) >= 0 { count = count + 1 }
        index = name_end
    }
    return count
}

func string_literal_index_at(string source, int wanted) int {
    int index = 0
    int ordinal = 0
    for index < wanted {
        if __host_char_at(source, index) == "\"" {
            int after = skip_quoted(source, index, wanted)
            if after > wanted { return -1 }
            ordinal = ordinal + 1
            index = after
            continue
        }
        index = index + 1
    }
    return ordinal
}

func string_literal_bytes(string source, int start, int end) string {
    string output = ""
    int index = start + 1
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\"" { return output }
        if ch == "\\" {
            index = index + 1
            if index >= end { return "" }
            ch = __host_char_at(source, index)
            if ch == "n" { ch = "\n" }
            if ch == "r" { ch = "\r" }
            if ch == "t" { ch = "\t" }
        }
        output = output + ch
        index = index + 1
    }
    return ""
}

func string_literal_pool(string source) string {
    string pool = ""
    int index = 0
    for index < len(source) {
        if __host_char_at(source, index) == "\"" {
            int after = skip_quoted(source, index, len(source))
            if after <= index { return "" }
            string literal = string_literal_bytes(source, index, after)
            if len(literal) >= 256 { return "" }
            pool = pool + literal + zeroes(256 - len(literal))
            index = after
            continue
        }
        index = index + 1
    }
    return pool
}

func string_literal_length(string source, int start, int end) int {
    if start >= end || __host_char_at(source, start) != "\"" { return -1 }
    int index = start + 1
    int count = 0
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\"" { return count }
        if ch == "\\" {
            index = index + 1
            if index >= end { return -1 }
        }
        count = count + 1
        index = index + 1
    }
    return -1
}

func emit_string_value_machine(string source, int raw_start, int raw_end, string current_function) string {
    int start = skip_space(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return "" }
    if __host_char_at(source, start) == "\"" {
        int length = string_literal_length(source, start, end)
        int close = skip_quoted(source, start, end)
        if length < 0 || close != end { return "" }
        int literal_index = string_literal_index_at(source, start)
        int function_count = native_function_count(source)
        if literal_index < 0 || function_count < 1 { return "" }
        int address = 4194304 + 120 + function_count * native_function_stride() + literal_index * 256
        return __host_byte_string(72) + __host_byte_string(184) + little64(address)
            + __host_byte_string(186) + little32(length)
    }
    int name_end = skip_identifier(source, start)
    string name = __host_slice(source, start, name_end)
    if name_end == end {
        int parameter = 0
        for function_parameter_at(source, current_function, parameter) != "" {
            if name == function_parameter_at(source, current_function, parameter) &&
                function_parameter_type_kind_at(source, current_function, parameter) == 3 {
                int offset = function_parameter_abi_offset(source, current_function, parameter)
                return stack_load(offset) + stack_load_rdx(offset + 1)
            }
            parameter = parameter + 1
        }
        int current_body = function_body(source, current_function)
        int local = local_slot(source, current_body, start, name)
        if local >= 0 && local_type_kind(source, current_body, start, name) == 3 {
            return stack_load(local + 6) + stack_load_rdx(local + 7)
        }
        return ""
    }
    int open = skip_space(source, name_end)
    if name_end == start || open >= end || __host_char_at(source, open) != "(" { return "" }
    int close = matching_paren(source, open, end)
    if close != end - 1 || function_return_type_kind(source, name) != 3 { return "" }
    int argument_start = skip_space(source, open + 1)
    string argument = ""
    if argument_start < close {
        argument = emit_typed_call_arguments(source, argument_start, close, current_function, name, 0)
        if argument == "" { return "" }
    } else if function_parameter(source, name) != "" { return "" }
    int slot = native_function_slot(source, name)
    int intrinsic_id = resolve_intrinsic_id(source, name)
    if slot <= 0 && intrinsic_id == 0 { return "" }
    if intrinsic_id != 0 { return argument + emit_intrinsic_machine(intrinsic_id) }
    int address = 4194304 + 120 + slot * native_function_stride()
    return argument
        + __host_byte_string(72) + __host_byte_string(184) + little64(address)
        + __host_byte_string(255) + __host_byte_string(208)
}

func emit_typed_call_arguments(
    string source,
    int raw_start,
    int end,
    string current_function,
    string callee,
    int ordinal
) string {
    int start = skip_space(source, raw_start)
    int kind = function_parameter_type_kind_at(source, callee, ordinal)
    int words = type_abi_words(kind)
    int word_offset = function_parameter_abi_offset(source, callee, ordinal)
    if start >= end || kind < 0 || word_offset + words > 16 { return "" }
    int comma = argument_comma(source, start, end)
    int argument_end = end
    if comma >= 0 { argument_end = comma }
    string value = emit_multi_condition_machine(source, start, argument_end, current_function)
    string pushes = __host_byte_string(80)
    string pops = ""
    if word_offset < 6 { pops = sysv_argument_pop(word_offset) }
    if kind == 3 {
        if word_offset + 1 >= 6 { return "" }
        value = emit_string_value_machine(source, start, argument_end, current_function)
        pushes = __host_byte_string(80) + __host_byte_string(82)
        pops = sysv_argument_pop(word_offset + 1) + sysv_argument_pop(word_offset)
    }
    if value == "" { return "" }
    if comma < 0 {
        if function_parameter_at(source, callee, ordinal + 1) != "" { return "" }
        return value + pushes + pops
    }
    string remaining = emit_typed_call_arguments(
        source,
        comma + 1,
        end,
        current_function,
        callee,
        ordinal + 1
    )
    if remaining == "" { return "" }
    return remaining + value + pushes + pops
}

func machine_drop_stack_arguments(string source, string callee) string {
    int words = function_parameter_abi_words(source, callee)
    if words <= 6 { return "" }
    return __host_byte_string(72) + __host_byte_string(129) + __host_byte_string(196)
        + little32((words - 6) * 8)
}

func emit_multi_call_arithmetic(string source, int raw_start, int raw_end, string current_function) string {
    int start = skip_space(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return "" }
    if matches_at(source, start, "len") {
        int len_open = skip_space(source, start + 3)
        if len_open < end && __host_char_at(source, len_open) == "(" {
            int len_close = matching_paren(source, len_open, end)
            if len_close == end - 1 {
                string string_value = emit_string_value_machine(source, len_open + 1, len_close, current_function)
                if string_value != "" {
                    return string_value + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(208)
                }
            }
        }
    }
    int bracket = start
    for bracket < end && __host_char_at(source, bracket) != "[" { bracket = bracket + 1 }
    if bracket < end && __host_char_at(source, end - 1) == "]" {
        int element_start = skip_space(source, bracket + 1)
        int element_end = trim_space_end(source, element_start, end - 1)
        int number_end = skip_uint(source, element_start)
        string string_value = emit_string_value_machine(source, start, bracket, current_function)
        if string_value != "" && number_end == element_end {
            int element = parse_uint(source, element_start)
            return string_value + __host_byte_string(15) + __host_byte_string(182)
                + __host_byte_string(128) + little32(element)
        }
    }
    if __host_char_at(source, start) == "(" {
        int close = matching_paren(source, start, end)
        if close == end - 1 { return emit_multi_call_arithmetic(source, start + 1, end - 1, current_function) }
    }
    int operator_at = arithmetic_operator_at(source, start, end, false)
    if operator_at < 0 { operator_at = arithmetic_operator_at(source, start, end, true) }
    if operator_at >= 0 {
        string simplified = simplify_binary_uint(source, start, operator_at, end)
        if simplified != "" { return simplified }
        string left = emit_multi_call_arithmetic(source, start, operator_at, current_function)
        string right = emit_multi_call_arithmetic(source, operator_at + 1, end, current_function)
        return machine_binary(left, right, __host_char_at(source, operator_at))
    }
    int number_end = skip_uint(source, start)
    if number_end == end { return __host_byte_string(184) + little32(parse_uint(source, start)) }
    int name_end = skip_identifier(source, start)
    string name = __host_slice(source, start, name_end)
    if name_end == end && name == "true" { return __host_byte_string(184) + little32(1) }
    if name_end == end && name == "false" { return __host_byte_string(184) + little32(0) }
    int open = skip_space(source, name_end)
    if name_end == end {
        int parameter_index = 0
        for parameter_index < 16 {
            if name == function_parameter_at(source, current_function, parameter_index) {
                int parameter_offset = function_parameter_abi_offset(source, current_function, parameter_index)
                return stack_load(parameter_offset)
            }
            parameter_index = parameter_index + 1
        }
        int current_body = function_body(source, current_function)
        int constant = compile_local_constant_value(source, current_body, start, name)
        if constant >= 0 { return __host_byte_string(184) + little32(constant) }
        int slot = local_slot(source, current_body, start, name)
        if slot >= 0 && slot < 25 { return stack_load(slot + 6) }
        return ""
    }
    if name_end <= start || open >= end || __host_char_at(source, open) != "(" { return "" }
    int close = matching_paren(source, open, end)
    if close != end - 1 { return "" }
    int slot = native_function_slot(source, name)
    string argument_code = ""
    int argument_start = skip_space(source, open + 1)
    if argument_start < close {
        argument_code = emit_typed_call_arguments(source, argument_start, close, current_function, name, 0)
        if argument_code == "" { return "" }
    } else if function_parameter(source, name) != "" {
        return ""
    }
    int intrinsic_id = resolve_intrinsic_id(source, name)
    if intrinsic_id != 0 { return argument_code + emit_intrinsic_machine(intrinsic_id) }
    if slot <= 0 { return "" }
    int address = 4194304 + 120 + slot * native_function_stride()
    return argument_code + __host_byte_string(72) + __host_byte_string(184) + little64(address)
        + __host_byte_string(255) + __host_byte_string(208)
        + machine_drop_stack_arguments(source, name)
}

func emit_multi_sysv_call_arguments(string source, int raw_start, int end, string current_function, string callee, int index) string {
    int start = skip_space(source, raw_start)
    if start >= end || index >= 6 || function_parameter_at(source, callee, index) == "" { return "" }
    int comma = argument_comma(source, start, end)
    int argument_end = end
    if comma >= 0 { argument_end = comma }
    string value = emit_multi_call_arithmetic(source, start, argument_end, current_function)
    string pop_argument = sysv_argument_pop(index)
    if value == "" || pop_argument == "" { return "" }
    if comma < 0 {
        if function_parameter_at(source, callee, index + 1) != "" { return "" }
        return value + __host_byte_string(80) + pop_argument
    }
    string remaining = emit_multi_sysv_call_arguments(source, comma + 1, end, current_function, callee, index + 1)
    if remaining == "" { return "" }
    return value + __host_byte_string(80) + remaining + pop_argument
}

func emit_multi_condition_machine(string source, int start, int end, string current_function) string {
    int trimmed_start = skip_space(source, start)
    int trimmed_end = trim_space_end(source, trimmed_start, end)
    if trimmed_start >= trimmed_end { return "" }
    if __host_char_at(source, trimmed_start) == "(" {
        int close = matching_paren(source, trimmed_start, trimmed_end)
        if close == trimmed_end - 1 {
            return emit_multi_condition_machine(source, trimmed_start + 1, trimmed_end - 1, current_function)
        }
    }
    int logical = logical_at(source, trimmed_start, trimmed_end, "||")
    if logical >= 0 {
        string simplified = simplify_logical_uint(source, trimmed_start, logical, trimmed_end)
        if simplified != "" { return simplified }
        string left_logical = emit_multi_condition_machine(source, trimmed_start, logical, current_function)
        string right_logical = emit_multi_condition_machine(source, logical + 2, trimmed_end, current_function)
        if left_logical == "" || right_logical == "" { return "" }
        return left_logical
            + machine_test_rax()
            + machine_jump_not_zero(len(right_logical))
            + right_logical
    }
    logical = logical_at(source, trimmed_start, trimmed_end, "&&")
    if logical >= 0 {
        string simplified = simplify_logical_uint(source, trimmed_start, logical, trimmed_end)
        if simplified != "" { return simplified }
        string left_logical = emit_multi_condition_machine(source, trimmed_start, logical, current_function)
        string right_logical = emit_multi_condition_machine(source, logical + 2, trimmed_end, current_function)
        if left_logical == "" || right_logical == "" { return "" }
        return left_logical
            + machine_test_rax()
            + machine_jump_zero(len(right_logical))
            + right_logical
    }
    if __host_char_at(source, trimmed_start) == "!" &&
        (trimmed_start + 1 >= trimmed_end || __host_char_at(source, trimmed_start + 1) != "=") {
        string negated = emit_multi_condition_machine(source, trimmed_start + 1, trimmed_end, current_function)
        if negated == "" { return "" }
        return negated
            + __host_byte_string(72) + __host_byte_string(133) + __host_byte_string(192)
            + __host_byte_string(15) + __host_byte_string(148) + __host_byte_string(192)
            + __host_byte_string(72) + __host_byte_string(15) + __host_byte_string(182) + __host_byte_string(192)
    }
    int compare = comparison_at(source, trimmed_start, trimmed_end)
    if compare < 0 { return emit_multi_call_arithmetic(source, trimmed_start, trimmed_end, current_function) }
    int operator_end = compare + 1
    if operator_end < trimmed_end && __host_char_at(source, operator_end) == "=" { operator_end = operator_end + 1 }
    string operator = __host_slice(source, compare, operator_end)
    string left = emit_multi_call_arithmetic(source, trimmed_start, compare, current_function)
    string right = emit_multi_call_arithmetic(source, operator_end, trimmed_end, current_function)
    return machine_compare(left, right, operator)
}

func emit_multi_assignment_block(string source, int block_start, int block_end, string function_name) string {
    int function_start = function_body(source, function_name)
    int index = block_start
    string code = ""
    for index < block_end {
        index = skip_space(source, index)
        if index >= block_end { return code }
        int name_end = skip_identifier(source, index)
        if name_end == index { return "" }
        string name = __host_slice(source, index, name_end)
        int assign = skip_space(source, name_end)
        if assign >= block_end || __host_char_at(source, assign) != "=" ||
            (assign + 1 < block_end && __host_char_at(source, assign + 1) == "=") { return "" }
        int expression_start = skip_space(source, assign + 1)
        int expression_finish = expression_end(source, expression_start)
        int slot = local_slot(source, function_start, index, name)
        string value = emit_multi_condition_machine(source, expression_start, expression_finish, function_name)
        if expression_finish < 0 || expression_finish > block_end || slot < 0 || slot >= 25 || value == "" { return "" }
        code = code + value + stack_store(slot + 6)
        index = expression_finish + 1
    }
    return code
}

func emit_multi_block_sequence(string source, int raw_start, int block_end, string function_name, bool entry_function) string {
    int index = skip_space(source, raw_start)
    if index >= block_end { return "" }
    if matches_at(source, index, "continue") {
        return continue_marker()
    }
    if matches_at(source, index, "break") {
        return break_marker()
    }
    if matches_at(source, index, "return") {
        int result_start = skip_space(source, index + 6)
        int result_end = expression_end(source, result_start)
        if result_end < 0 || result_end > block_end { return "" }
        int return_kind = function_return_type_kind(source, function_name)
        string result = emit_multi_call_arithmetic(source, result_start, result_end, function_name)
        if return_kind == 2 {
            result = emit_multi_condition_machine(source, result_start, result_end, function_name)
        }
        if return_kind == 3 {
            result = emit_string_value_machine(source, result_start, result_end, function_name)
        }
        if result == "" { return "" }
        if entry_function {
            return result + __host_byte_string(72) + __host_byte_string(137)
                + __host_byte_string(199) + exit_sequence()
        }
        return result + __host_byte_string(201) + __host_byte_string(195)
    }
    if matches_at(source, index, "if") {
        int condition_start = skip_space(source, index + 2)
        int open = condition_start
        int depth = 0
        for open < block_end {
            string ch = __host_char_at(source, open)
            if ch == "(" { depth = depth + 1 }
            if ch == ")" { depth = depth - 1 }
            if ch == "{" && depth == 0 { break }
            open = open + 1
        }
        if open >= block_end { return "" }
        int close = function_body_end(source, open + 1)
        if close < 0 || close > block_end { return "" }
        int condition_value = emit_multi_condition_constant(source, condition_start, open)
        if condition_value == 1 {
            string then_only = emit_multi_block_sequence(source, open + 1, close, function_name, entry_function)
            if then_only == "" { return "" }
            return then_only + emit_multi_block_sequence(source, close + 1, block_end, function_name, entry_function)
        }
        if condition_value == 0 {
            int after = skip_space(source, close + 1)
            if after < block_end && matches_at(source, after, "else") {
                int else_open = skip_space(source, after + 4)
                if else_open >= block_end || __host_char_at(source, else_open) != "{" { return "" }
                int else_close = function_body_end(source, else_open + 1)
                if else_close < 0 || else_close > block_end { return "" }
                string else_code = emit_multi_block_sequence(source, else_open + 1, else_close, function_name, entry_function)
                if else_code == "" { return "" }
                return else_code + emit_multi_block_sequence(source, else_close + 1, block_end, function_name, entry_function)
            }
        }
        string condition = emit_multi_condition_machine(source, condition_start, open, function_name)
        string then_code = emit_multi_block_sequence(source, open + 1, close, function_name, entry_function)
        if condition == "" { return "" }
        string test_result = machine_test_rax()
        int after = skip_space(source, close + 1)
        if after < block_end && matches_at(source, after, "else") {
            int else_open = skip_space(source, after + 4)
            if else_open >= block_end || __host_char_at(source, else_open) != "{" { return "" }
            int else_close = function_body_end(source, else_open + 1)
            if else_close < 0 || else_close > block_end { return "" }
            string else_code = emit_multi_block_sequence(source, else_open + 1, else_close, function_name, entry_function)
            string rest = emit_multi_block_sequence(source, else_close + 1, block_end, function_name, entry_function)
            return condition + test_result
                + machine_jump_zero(len(then_code) + 5)
                + then_code + machine_jump(len(else_code))
                + else_code + rest
        }
        string rest = emit_multi_block_sequence(source, close + 1, block_end, function_name, entry_function)
        return condition + test_result
            + machine_jump_zero(len(then_code))
            + then_code + rest
    }
    if matches_at(source, index, "while") || matches_at(source, index, "for") {
        int keyword_size = 5
        if matches_at(source, index, "for") { keyword_size = 3 }
        int condition_start = skip_space(source, index + keyword_size)
        int open = condition_start
        for open < block_end && __host_char_at(source, open) != "{" { open = open + 1 }
        if open >= block_end { return "" }
        int close = function_body_end(source, open + 1)
        if close < 0 || close > block_end { return "" }
        string condition = emit_multi_condition_machine(source, condition_start, open, function_name)
        string loop_body = emit_multi_block_sequence(source, open + 1, close, function_name, entry_function)
        if condition == "" || loop_body == "" { return "" }
        string rest = emit_multi_block_sequence(source, close + 1, block_end, function_name, entry_function)
        return machine_while(condition, loop_body) + rest
    }
    int name_end = skip_identifier(source, index)
    if name_end == index { return "" }
    string name = __host_slice(source, index, name_end)
    int assign = skip_space(source, name_end)
    int declaration_kind = parse_type_kind(name)
    bool typed_declaration = declaration_kind == 1 || declaration_kind == 2 || declaration_kind == 3
    if typed_declaration {
        int typed_name_at = assign
        int typed_name_end = skip_identifier(source, typed_name_at)
        if typed_name_end == typed_name_at { return "" }
        name = __host_slice(source, typed_name_at, typed_name_end)
        name_end = typed_name_end
        assign = skip_space(source, typed_name_end)
        if assign >= block_end || __host_char_at(source, assign) != "=" ||
            (assign + 1 < block_end && __host_char_at(source, assign + 1) == "=") { return "" }
    }
    bool declaration = assign + 1 < block_end && __host_char_at(source, assign) == ":" &&
        __host_char_at(source, assign + 1) == "="
    bool assignment = assign < block_end && __host_char_at(source, assign) == "=" &&
        !(assign + 1 < block_end && __host_char_at(source, assign + 1) == "=")
    if declaration || assignment || typed_declaration {
        int initializer = skip_space(source, assign + 1)
        if declaration { initializer = skip_space(source, assign + 2) }
        int initializer_end = expression_end(source, initializer)
        int function_start = function_body(source, function_name)
        int slot = local_slot(source, function_start, index, name)
        int value_kind = declaration_kind
        if !typed_declaration { value_kind = local_type_kind(source, function_start, index, name) }
        string value = emit_multi_condition_machine(source, initializer, initializer_end, function_name)
        if value_kind == 3 { value = emit_string_value_machine(source, initializer, initializer_end, function_name) }
        if initializer_end < 0 || initializer_end > block_end || slot < 0 || slot >= 25 || value == "" { return "" }
        string store = stack_store(slot + 6)
        if value_kind == 3 { store = store + stack_store_rdx(slot + 7) }
        return value + store
            + emit_multi_block_sequence(source, initializer_end + 1, block_end, function_name, entry_function)
    }
    int expression_finish = expression_end(source, index)
    if expression_finish < 0 || expression_finish > block_end { return "" }
    string expression_code = emit_multi_call_arithmetic(source, index, expression_finish, function_name)
    if expression_code == "" { return "" }
    return expression_code
        + emit_multi_block_sequence(source, expression_finish + 1, block_end, function_name, entry_function)
}

func emit_multi_function_machine(string source, string function_name, bool entry_function) string {
    int body = function_body(source, function_name)
    if body < 0 { return "" }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return "" }
    string statements = emit_multi_block_sequence(source, body + 1, body_end, function_name, entry_function)
    if statements == "" { return "" }
    return spill_sysv_parameters(function_parameter_abi_words(source, function_name)) + statements
}

func emit_native_multi_call_elf(string source) string {
    int stride = native_function_stride()
    string main_code = emit_multi_function_machine(source, "main", true)
    if main_code == "" { return "" }
    if len(main_code) > stride { return "" }
    string image = main_code + zeroes(stride - len(main_code))
    int index = 0
    int emitted = 0
    for index < len(source) {
        int declaration = find_function_from(source, index)
        if declaration < 0 { break }
        int name_at = skip_space(source, declaration + 4)
        int name_end = skip_identifier(source, name_at)
        if name_end == name_at { return "" }
        string name = __host_slice(source, name_at, name_end)
        if name != "main" && function_body(source, name) >= 0 {
            if function_parameter_abi_words(source, name) > 16 { return "" }
            string code = emit_multi_function_machine(source, name, false)
            if code == "" { return "" }
            if len(code) > stride { return "" }
            image = image + code + zeroes(stride - len(code))
            emitted = emitted + 1
        }
        index = name_end
    }
    string literal_pool = string_literal_pool(source)
    return emit_elf_image(image + literal_pool)
}

func emit_native_copy_elf(string source) string {
    int body = function_body(source, "main")
    if body < 0 { return "" }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return "" }
    int call_at = skip_space(source, body + 1)
    if call_at >= body_end || !matches_at(source, call_at, "copy_args_file") { return "" }
    string setup = __host_byte_string(72) + __host_byte_string(139) + __host_byte_string(92)
        + __host_byte_string(36) + __host_byte_string(16)
        + __host_byte_string(76) + __host_byte_string(139) + __host_byte_string(108)
        + __host_byte_string(36) + __host_byte_string(24)
        + __host_byte_string(72) + __host_byte_string(129) + __host_byte_string(236) + little32(4096)
    string test_rax = __host_byte_string(72) + __host_byte_string(133) + __host_byte_string(192)
    string success_exit = __host_byte_string(191) + little32(0)
        + __host_byte_string(184) + little32(60)
        + __host_byte_string(15) + __host_byte_string(5)
    string io_exit = __host_byte_string(191) + little32(1)
        + __host_byte_string(184) + little32(60)
        + __host_byte_string(15) + __host_byte_string(5)
    string open_input_call = __host_byte_string(72) + __host_byte_string(199) + __host_byte_string(199) + little32_signed(-100)
        + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(222)
        + __host_byte_string(49) + __host_byte_string(210)
        + __host_byte_string(69) + __host_byte_string(49) + __host_byte_string(210)
        + __host_byte_string(184) + little32(257)
        + __host_byte_string(15) + __host_byte_string(5)
    string save_input = __host_byte_string(73) + __host_byte_string(137) + __host_byte_string(196)
    string open_output_call = __host_byte_string(72) + __host_byte_string(199) + __host_byte_string(199) + little32_signed(-100)
        + __host_byte_string(76) + __host_byte_string(137) + __host_byte_string(238)
        + __host_byte_string(186) + little32(577)
        + __host_byte_string(65) + __host_byte_string(186) + little32(420)
        + __host_byte_string(184) + little32(257)
        + __host_byte_string(15) + __host_byte_string(5)
    string save_output = __host_byte_string(73) + __host_byte_string(137) + __host_byte_string(199)
    string read_call = __host_byte_string(76) + __host_byte_string(137) + __host_byte_string(231)
        + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(230)
        + __host_byte_string(186) + little32(4096)
        + __host_byte_string(49) + __host_byte_string(192)
        + __host_byte_string(15) + __host_byte_string(5)
    string begin_write = __host_byte_string(73) + __host_byte_string(137) + __host_byte_string(198)
        + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(227)
    string write_call = __host_byte_string(76) + __host_byte_string(137) + __host_byte_string(255)
        + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(222)
        + __host_byte_string(76) + __host_byte_string(137) + __host_byte_string(242)
        + __host_byte_string(184) + little32(1)
        + __host_byte_string(15) + __host_byte_string(5)
    string advance_write = __host_byte_string(72) + __host_byte_string(1) + __host_byte_string(195)
        + __host_byte_string(73) + __host_byte_string(41) + __host_byte_string(198)
    int write_back = 0 - (len(write_call) + len(test_rax) + 6 + len(advance_write) + 6)
    string write_loop_without_read_jump = write_call + test_rax
        + __host_byte_string(15) + __host_byte_string(142)
        + little32(len(advance_write) + 6 + 5 + len(success_exit))
        + advance_write
        + __host_byte_string(15) + __host_byte_string(133) + little32_signed(write_back)
    int read_head_size = len(read_call) + len(test_rax) + 6 + 6 + len(begin_write)
    int read_back = 0 - (read_head_size + len(write_loop_without_read_jump) + 5)
    string write_loop = write_loop_without_read_jump
        + __host_byte_string(233) + little32_signed(read_back)
    string read_loop = read_call + test_rax
        + __host_byte_string(15) + __host_byte_string(136)
        + little32(6 + len(begin_write) + len(write_loop) + len(success_exit))
        + __host_byte_string(15) + __host_byte_string(132)
        + little32(len(begin_write) + len(write_loop))
        + begin_write + write_loop
    string open_output = open_output_call + test_rax
        + __host_byte_string(15) + __host_byte_string(136)
        + little32(len(save_output) + len(read_loop) + len(success_exit))
        + save_output
    string open_input = open_input_call + test_rax
        + __host_byte_string(15) + __host_byte_string(136)
        + little32(len(save_input) + len(open_output) + len(read_loop) + len(success_exit))
        + save_input
    string code = setup + open_input + open_output + read_loop + success_exit + io_exit
    string argc_check = __host_byte_string(72) + __host_byte_string(131)
        + __host_byte_string(60) + __host_byte_string(36) + __host_byte_string(3)
        + __host_byte_string(15) + __host_byte_string(133) + little32(len(code))
    string usage_exit = __host_byte_string(191) + little32(2)
        + __host_byte_string(184) + little32(60)
        + __host_byte_string(15) + __host_byte_string(5)
    return emit_elf_image(argc_check + code + usage_exit)
}

func emit_native_locals_elf(string source) string {
    int body = function_body(source, "main")
    if body < 0 { return "" }
    int body_end = function_body_end(source, body + 1)
    if body_end < 0 { return "" }
    string code = __host_byte_string(85) + __host_byte_string(72) + __host_byte_string(137)
        + __host_byte_string(229) + __host_byte_string(72) + __host_byte_string(129)
        + __host_byte_string(236) + little32(128)
    int index = body + 1
    for index < body_end {
        index = skip_space(source, index)
        if index >= body_end { return "" }
        if matches_at(source, index, "return") {
            int return_start = skip_space(source, index + 6)
            int return_end = expression_end(source, return_start)
            if return_end < 0 || return_end > body_end { return "" }
            string result = emit_scoped_arithmetic_machine(source, return_start, return_end, body + 1)
            if result == "" { return "" }
            string move_result = __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(199)
            return emit_elf_image(code + result + move_result + exit_sequence())
        }
        if !is_alpha(__host_char_at(source, index)) { return "" }
        int name_end = skip_identifier(source, index)
        int assign = skip_space(source, name_end)
        if assign + 1 >= body_end || __host_char_at(source, assign) != ":" ||
            __host_char_at(source, assign + 1) != "=" { return "" }
        int initializer = skip_space(source, assign + 2)
        int initializer_end = expression_end(source, initializer)
        if initializer_end < 0 || initializer_end > body_end { return "" }
        string value = emit_scoped_arithmetic_machine(source, initializer, initializer_end, body + 1)
        int slot = local_slot(source, body + 1, index, __host_slice(source, index, name_end))
        if value == "" || slot < 0 || slot >= 15 { return "" }
        code = code + value + stack_store(slot)
        index = initializer_end + 1
    }
    return ""
}

func called_function_name(string source, int start, int end) string {
    int index = start
    for index < end {
        if is_alpha(__host_char_at(source, index)) {
            int name_end = skip_identifier(source, index)
            int open = skip_space(source, name_end)
            if open < end && __host_char_at(source, open) == "(" {
                int close = matching_paren(source, open, end)
                if close >= 0 { return __host_slice(source, index, name_end) }
            }
            index = name_end
            continue
        }
        index = index + 1
    }
    return ""
}

func emit_call_arithmetic_machine(string source, int raw_start, int raw_end, string callee, int callee_address) string {
    int start = skip_space(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return "" }
    if __host_char_at(source, start) == "(" {
        int close = matching_paren(source, start, end)
        if close == end - 1 {
            return emit_call_arithmetic_machine(source, start + 1, end - 1, callee, callee_address)
        }
    }
    int operator_at = arithmetic_operator_at(source, start, end, false)
    if operator_at < 0 { operator_at = arithmetic_operator_at(source, start, end, true) }
    if operator_at >= 0 {
        string left = emit_call_arithmetic_machine(source, start, operator_at, callee, callee_address)
        string right = emit_call_arithmetic_machine(source, operator_at + 1, end, callee, callee_address)
        return machine_binary(left, right, __host_char_at(source, operator_at))
    }
    int number_end = skip_uint(source, start)
    if number_end == end { return __host_byte_string(184) + little32(parse_uint(source, start)) }
    int name_end = skip_identifier(source, start)
    int open = skip_space(source, name_end)
    if name_end > start && __host_slice(source, start, name_end) == callee && open < end &&
        __host_char_at(source, open) == "(" {
        int close = matching_paren(source, open, end)
        if close == end - 1 {
            string argument_code = ""
            int argument_start = skip_space(source, open + 1)
            if argument_start < close {
                argument_code = emit_sysv_call_arguments(source, argument_start, close, callee, callee_address, 0)
                if argument_code == "" { return "" }
            } else if function_parameter(source, callee) != "" {
                return ""
            }
            return argument_code + __host_byte_string(72) + __host_byte_string(184) + little64(callee_address)
                + __host_byte_string(255) + __host_byte_string(208)
        }
    }
    return ""
}

func argument_comma(string source, int start, int end) int {
    int index = start
    int depth = 0
    for index < end {
        string ch = __host_char_at(source, index)
        if ch == "\"" { index = skip_quoted(source, index, end); continue }
        if ch == "(" { depth = depth + 1 }
        if ch == ")" { depth = depth - 1 }
        if depth == 0 && ch == "," { return index }
        index = index + 1
    }
    return -1
}

func sysv_argument_pop(int index) string {
    if index == 0 { return __host_byte_string(95) }
    if index == 1 { return __host_byte_string(94) }
    if index == 2 { return __host_byte_string(90) }
    if index == 3 { return __host_byte_string(89) }
    if index == 4 { return __host_byte_string(65) + __host_byte_string(88) }
    if index == 5 { return __host_byte_string(65) + __host_byte_string(89) }
    return ""
}

func emit_sysv_call_arguments(string source, int raw_start, int end, string callee, int callee_address, int index) string {
    int start = skip_space(source, raw_start)
    if start >= end || index >= 6 || function_parameter_at(source, callee, index) == "" { return "" }
    int comma = argument_comma(source, start, end)
    int argument_end = end
    if comma >= 0 { argument_end = comma }
    string value = emit_call_arithmetic_machine(source, start, argument_end, callee, callee_address)
    string pop_argument = sysv_argument_pop(index)
    if value == "" || pop_argument == "" { return "" }
    if comma < 0 {
        if function_parameter_at(source, callee, index + 1) != "" { return "" }
        return value + __host_byte_string(80) + pop_argument
    }
    string remaining = emit_sysv_call_arguments(source, comma + 1, end, callee, callee_address, index + 1)
    if remaining == "" { return "" }
    return value + __host_byte_string(80) + remaining + pop_argument
}

func sysv_parameter_load(int index) string {
    if index == 0 { return __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(248) }
    if index == 1 { return __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(240) }
    if index == 2 { return __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(208) }
    if index == 3 { return __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(200) }
    if index == 4 { return __host_byte_string(76) + __host_byte_string(137) + __host_byte_string(192) }
    if index == 5 { return __host_byte_string(76) + __host_byte_string(137) + __host_byte_string(200) }
    if index < 16 {
        return __host_byte_string(72) + __host_byte_string(139) + __host_byte_string(69)
            + __host_byte_string(16 + (index - 6) * 8)
    }
    return ""
}

func spill_sysv_parameters(int words) string {
    string code = __host_byte_string(85)
        + __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(229)
        + __host_byte_string(72) + __host_byte_string(129) + __host_byte_string(236) + little32(256)
    int index = 0
    for index < words && index < 16 {
        code = code + sysv_parameter_load(index) + stack_store(index)
        index = index + 1
    }
    return code
}

func emit_parameters_arithmetic_machine(string source, int raw_start, int raw_end, string function_name) string {
    int start = skip_space(source, raw_start)
    int end = trim_space_end(source, start, raw_end)
    if start >= end { return "" }
    if __host_char_at(source, start) == "(" {
        int close = matching_paren(source, start, end)
        if close == end - 1 {
            return emit_parameters_arithmetic_machine(source, start + 1, end - 1, function_name)
        }
    }
    int operator_at = arithmetic_operator_at(source, start, end, false)
    if operator_at < 0 { operator_at = arithmetic_operator_at(source, start, end, true) }
    if operator_at >= 0 {
        string left = emit_parameters_arithmetic_machine(source, start, operator_at, function_name)
        string right = emit_parameters_arithmetic_machine(source, operator_at + 1, end, function_name)
        return machine_binary(left, right, __host_char_at(source, operator_at))
    }
    int number_end = skip_uint(source, start)
    if number_end == end { return __host_byte_string(184) + little32(parse_uint(source, start)) }
    int name_end = skip_identifier(source, start)
    string identifier = __host_slice(source, start, name_end)
    int parameter_index = 0
    for parameter_index < 16 {
        if name_end == end && identifier == function_parameter_at(source, function_name, parameter_index) {
            return stack_load(parameter_index)
        }
        parameter_index = parameter_index + 1
    }
    return ""
}

func emit_native_call_elf(string source) string {
    int main_body = function_body(source, "main")
    if main_body < 0 { return "" }
    int main_end = function_body_end(source, main_body + 1)
    if main_end < 0 { return "" }
    int main_return = skip_space(source, main_body + 1)
    if main_return >= main_end || !matches_at(source, main_return, "return") { return "" }
    int main_expression = skip_space(source, main_return + 6)
    int main_expression_end = expression_end(source, main_expression)
    if main_expression_end < 0 || main_expression_end > main_end { return "" }
    int after_main = main_expression_end
    if after_main < main_end && __host_char_at(source, after_main) == ";" { after_main = after_main + 1 }
    after_main = skip_space(source, after_main)
    if after_main != main_end { return "" }
    string callee = called_function_name(source, main_expression, main_expression_end)
    if callee == "" || callee == "main" { return "" }
    int callee_body = function_body(source, callee)
    if callee_body < 0 { return "" }
    int callee_end = function_body_end(source, callee_body + 1)
    if callee_end < 0 { return "" }
    int callee_return = find_word_from(source, "return", callee_body + 1)
    if callee_return < 0 || callee_return >= callee_end { return "" }
    int callee_expression = skip_space(source, callee_return + 6)
    int callee_expression_end = expression_end(source, callee_expression)
    if callee_expression_end < 0 || callee_expression_end > callee_end { return "" }
    int image_base = 4194304
    int code_offset = 120
    int function_slot = 512
    int callee_address = image_base + code_offset + function_slot
    string main_code = emit_call_arithmetic_machine(source, main_expression, main_expression_end, callee, callee_address)
    string callee_code = ""
    if function_parameter(source, callee) == "" {
        callee_code = emit_arithmetic_machine(source, callee_expression, callee_expression_end)
    } else {
        if function_parameter_at(source, callee, 16) != "" { return "" }
        string parameter_expression = emit_parameters_arithmetic_machine(source, callee_expression, callee_expression_end, callee)
        if parameter_expression == "" { return "" }
        callee_code = spill_sysv_parameters(function_parameter_abi_words(source, callee)) + parameter_expression
    }
    if main_code == "" || callee_code == "" || len(main_code) + 12 > function_slot { return "" }
    string move_result = __host_byte_string(72) + __host_byte_string(137) + __host_byte_string(199)
    main_code = main_code + move_result + exit_sequence()
    if function_parameter(source, callee) == "" {
        callee_code = callee_code + __host_byte_string(195)
    } else {
        callee_code = callee_code + __host_byte_string(201) + __host_byte_string(195)
    }
    return emit_elf_image(main_code + zeroes(function_slot - len(main_code)) + callee_code)
}

func compile_binary(string source, string output_path) int {
    int exit_code = evaluate_main_expression(source)
    if exit_code < 0 {
        eprintln("compile: source is outside bootstrap slice 1")
        return 1
    }
    if __host_write_text_file(output_path, emit_exit_elf(exit_code)) != 0 {
        eprintln("compile: cannot write executable")
        return 1
    }
    if __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot mark output executable")
        return 1
    }
    return 0
}

func compile_native_expression_binary(string source, string output_path) int {
    string elf = emit_native_expression_elf(source)
    if elf == "" {
        eprintln("compile: source is outside native expression slice")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native expression executable")
        return 1
    }
    return 0
}

func compile_native_control_binary(string source, string output_path) int {
    string elf = emit_native_control_elf(source)
    if elf == "" {
        eprintln("compile: source is outside native control slice")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native control executable")
        return 1
    }
    return 0
}

func compile_native_locals_binary(string source, string output_path) int {
    string elf = emit_native_locals_elf(source)
    if elf == "" {
        eprintln("compile: source is outside native locals slice")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native locals executable")
        return 1
    }
    return 0
}

func compile_native_call_binary(string source, string output_path) int {
    string elf = emit_native_call_elf(source)
    if elf == "" {
        eprintln("compile: source is outside native call slice")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native call executable")
        return 1
    }
    return 0
}

func compile_native_loop_binary(string source, string output_path) int {
    string elf = emit_native_loop_elf(source)
    if elf == "" {
        eprintln("compile: source is outside native loop slice")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native loop executable")
        return 1
    }
    return 0
}

func compile_native_string_binary(string source, string output_path) int {
    string elf = emit_native_string_elf(source)
    if elf == "" {
        eprintln("compile: source is outside native string slice")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native string executable")
        return 1
    }
    return 0
}

func compile_native_array_binary(string source, string output_path) int {
    string elf = emit_native_array_elf(source)
    if elf == "" {
        eprintln("compile: source is outside native array slice")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native array executable")
        return 1
    }
    return 0
}

func compile_native_multi_call_binary(string source, string output_path) int {
    string elf = emit_native_multi_call_elf(source)
    if elf == "" {
        eprintln("compile: source is outside native multi-call slice")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native multi-call executable")
        return 1
    }
    return 0
}

func compile_native_copy_binary(string source, string output_path) int {
    string elf = emit_native_copy_elf(source)
    if elf == "" {
        eprintln("compile: source is outside native copy slice")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native copy executable")
        return 1
    }
    return 0
}

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
        return left_or + "    cmp $1, %rax\n    jne .Las_or_done_" + or_label + "\n"
            + right_or + ".Las_or_done_" + or_label + ":\n"
    }
    logical = logical_at(source, start, end, "&&")
    if logical >= 0 {
        string left_and = asm_expression(source, start, logical, function_name)
        string right_and = asm_expression(source, logical + 2, end, function_name)
        if left_and == "" || right_and == "" { return "" }
        string and_label = int_text(logical)
        return left_and + "    cmp $1, %rax\n    je .Las_and_done_" + and_label + "\n"
            + right_and + ".Las_and_done_" + and_label + ":\n"
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
        return left_compare + "    push %rax\n" + right_compare
            + "    mov %rax, %rsi\n    pop %rdi\n    call s_value_cmp\n    cmp $0, %rax\n"
            + asm_comparison(operator) + "    movzbq %al, %rax\n    lea 1(%rax,%rax), %rax\n"
    }
    int operator_at = arithmetic_operator_at(source, start, end, false)
    if operator_at < 0 { operator_at = arithmetic_operator_at(source, start, end, true) }
    if operator_at >= 0 {
        string left = asm_expression(source, start, operator_at, function_name)
        string right = asm_expression(source, operator_at + 1, end, function_name)
        if left == "" || right == "" { return "" }
        string operator = __host_char_at(source, operator_at)
        if operator == "+" {
            return left + "    push %rax\n" + right
                + "    mov %rax, %rsi\n    pop %rdi\n    call s_value_add\n"
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
        return collection + "    push %rax\n" + subscript
            + "    mov %rax, %rsi\n    pop %rdi\n    call s_index_get\n"
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
                return condition + "    cmp $1, %rax\n    je .Las_else_" + label + "\n"
                    + then_code + "    jmp .Las_if_done_" + label + "\n.Las_else_" + label + ":\n"
                    + else_if_code + ".Las_if_done_" + label + ":\n" + rest_after_else_if
            }
            if else_open >= block_end || __host_char_at(source, else_open) != "{" { return "" }
            int else_close = function_body_end(source, else_open + 1)
            if else_close < 0 || else_close > block_end { return "" }
            string else_code = asm_block_loop(source, else_open + 1, else_close, function_name, loop_start, loop_end)
            string rest_after_else = asm_block_loop(source, else_close + 1, block_end, function_name, loop_start, loop_end)
            return condition + "    cmp $1, %rax\n    je .Las_else_" + label + "\n"
                + then_code + "    jmp .Las_if_done_" + label + "\n.Las_else_" + label + ":\n"
                + else_code + ".Las_if_done_" + label + ":\n" + rest_after_else
        }
        string rest_after_if = asm_block_loop(source, close + 1, block_end, function_name, loop_start, loop_end)
        return condition + "    cmp $1, %rax\n    je .Las_if_done_" + label + "\n"
            + then_code + ".Las_if_done_" + label + ":\n" + rest_after_if
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
        return start_label + ":\n" + condition + "    cmp $1, %rax\n    je " + end_label + "\n"
            + body_code + "    jmp " + start_label + "\n" + end_label + ":\n" + rest_after_loop
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
        return default_value + default_store
            + asm_block_loop(source, name_end, block_end, function_name, loop_start, loop_end)
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
        + ":\n    push %rbp\n    mov %rsp, %rbp\n    sub $4096, %rsp\n"
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
    return code + body_code + "    mov $1, %rax\n.Las_return_" + name
        + ":\n    leave\n    ret\n.size s_fn_" + name + ", .-s_fn_" + name + "\n\n"
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
            + ":\n    .quad 2\n    .quad " + int_text(count) + "\n    .byte " + bytes + "0\n"
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

func compile_native_binary(string source, string output_path) int {
    string elf = emit_native_auto_elf(source)
    if elf == "" {
        eprintln("compile: source is outside implemented native slices")
        return 1
    }
    if __host_write_text_file(output_path, elf) != 0 || __host_make_executable(output_path) != 0 {
        eprintln("compile: cannot write native executable")
        return 1
    }
    return 0
}

func main() {
    args := host_args()
    if len(args) != 3 && len(args) != 4 && len(args) != 5 {
        eprintln("usage: s build <input.s> -o <output>")
        eprintln("       s [--report-unsupported|--emit-bin|--emit-native|--emit-asm] <input.s> <output>")
        return 2
    }
    bool build_native = len(args) == 5 && args[1] == "build" && args[3] == "-o"
    if len(args) == 5 && !build_native {
        eprintln("usage: s build <input.s> -o <output>")
        return 2
    }
    bool report_unsupported = len(args) == 4 && args[1] == "--report-unsupported"
    bool binary = len(args) == 4 && args[1] == "--emit-bin"
    bool native_expression = len(args) == 4 && args[1] == "--emit-native-expr"
    bool native_control = len(args) == 4 && args[1] == "--emit-native-control"
    bool native_locals = len(args) == 4 && args[1] == "--emit-native-locals"
    bool native_call = len(args) == 4 && args[1] == "--emit-native-call"
    bool native_loop = len(args) == 4 && args[1] == "--emit-native-loop"
    bool native_string = len(args) == 4 && args[1] == "--emit-native-string"
    bool native = (len(args) == 4 && args[1] == "--emit-native") || build_native
    bool native_array = len(args) == 4 && args[1] == "--emit-native-array"
    bool native_multi_call = len(args) == 4 && args[1] == "--emit-native-multicall"
    bool native_copy = len(args) == 4 && args[1] == "--emit-native-copy"
    bool native_assembly = len(args) == 4 && args[1] == "--emit-asm"
    bool debug_find = len(args) == 4 && args[1] == "--debug-find"
    int input_index = 1
    int output_index = 2
    if build_native {
        input_index = 2
        output_index = 4
    } else if report_unsupported || binary || native_expression || native_control || native_locals || native_call || native_loop || native_string || native || native_array || native_multi_call || native_copy || native_assembly || debug_find {
        input_index = 2
        output_index = 3
    }
    string source = __host_read_to_string(args[input_index])
    if len(source) == 0 {
        eprintln("compile: cannot read input or input is empty")
        return 1
    }
    if debug_find {
        int found = find_function_from(source, 0)
        int body = function_body(source, "main")
        return __host_write_text_file(args[output_index], int_text(found) + "|" + int_text(body))
    }
    if !native_assembly && parse_package_name(source) == "" {
        eprintln("compile: invalid or missing package declaration")
        return 1
    }
    if !native_assembly && intrinsic_declaration_count(source) < 0 {
        eprintln("compile: invalid extern intrinsic declaration")
        return 1
    }
    if !native_assembly && !debug_find && !validate_function_symbols(source) {
        eprintln("compile: invalid function symbol table")
        return 1
    }
    if report_unsupported {
        if __host_write_text_file(args[output_index], unsupported_report(source)) != 0 {
            eprintln("compile: cannot write unsupported capability report")
            return 1
        }
        return 0
    }
    if binary {
        return compile_binary(source, args[output_index])
    }
    if native_expression {
        return compile_native_expression_binary(source, args[output_index])
    }
    if native_control {
        return compile_native_control_binary(source, args[output_index])
    }
    if native_locals {
        return compile_native_locals_binary(source, args[output_index])
    }
    if native_call {
        return compile_native_call_binary(source, args[output_index])
    }
    if native_loop {
        return compile_native_loop_binary(source, args[output_index])
    }
    if native_string {
        return compile_native_string_binary(source, args[output_index])
    }
    if native {
        return compile_native_binary(source, args[output_index])
    }
    if native_array {
        return compile_native_array_binary(source, args[output_index])
    }
    if native_multi_call {
        return compile_native_multi_call_binary(source, args[output_index])
    }
    if native_copy {
        return compile_native_copy_binary(source, args[output_index])
    }
    if native_assembly {
        return compile_native_assembly(source, args[output_index])
    }
    string ir = compile_main_expression(source)
    if len(ir) == 0 {
        eprintln("compile: source is outside bootstrap slice 1")
        return 1
    }
    if __host_write_text_file(args[output_index], ir) != 0 {
        eprintln("compile: cannot write output")
        return 1
    }
    return 0
}
