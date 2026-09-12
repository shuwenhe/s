package compile.compiler
extern "intrinsic" func host_args() string[];
extern "intrinsic" func __host_read_to_string(string path) string;
extern "intrinsic" func __host_write_text_file(string path, string contents) int;
extern "intrinsic" func __host_char_at(string text, int index) string;
extern "intrinsic" func __host_slice(string text, int start, int end) string;

struct compiler_state {
    string source
    int pos
    int line
    string token
    string error
    string code
    string[] names
    int[] kinds
    int[] live
    int[] roots
    int[] parents
    int[] loan_fields
    int[] loan_parent_fields
    int[] array_lengths
    int[] struct_ids
    int[] field_state
    int[] field_borrow_state
    int[] nested_field_state
    int[] nested_field_borrow_state
    int count
    int loop_floor
    int loop_cleanup
    int depth
    int expr_depth
    int terminated
    string value
    int value_kind
    int value_slot
    int value_parent
    int value_field
    int value_parent_field
    int value_array_length
    int value_struct_id
    bool new_borrow
    string[] function_names
    int[] function_counts
    int[] function_returns
    int[] function_return_params
    int return_kind
    int parameter_count
    int return_param
    int[] function_starts
    int[] function_param_kinds
    int[] function_param_structs
    int[] function_return_structs
    int function_count
    int function_param_total
    string[] struct_names
    string[] struct_field_lefts
    string[] struct_field_rights
    int[] struct_field_left_kinds
    int[] struct_field_right_kinds
    string[] struct_field_names
    int[] struct_field_kinds
    int[] struct_field_structs
    int[] struct_field_starts
    int[] struct_field_counts
    int[] struct_custom_drops
    int struct_count
    string function_name
    bool function_main
    string[] method_names
    int[] method_structs
    int[] method_returns
    int method_count
}

func compiler_number(int n) string {
    string digits = "0123456789"
    if n < 10 { return __host_char_at(digits, n) }
    return compiler_number(n / 10) + __host_char_at(digits, n % 10)
}

func compiler_digit(string c) bool { return c != "" && c >= "0" && c <= "9" }

func compiler_alpha(string c) bool {
    return c != "" && ((c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_")
}

func compiler_ident(string t) bool {
    if !compiler_alpha(__host_char_at(t, 0)) { return false }
    int i = 1
    for i < len(t) {
        string c = __host_char_at(t, i)
        if !compiler_alpha(c) && !compiler_digit(c) { return false }
        i = i + 1
    }
    return true
}

func compiler_fail(compiler_state initial, string message) compiler_state {
    s := initial
    if s.error == "" { s.error = "compiler:" + compiler_number(s.line) + ": " + message }
    return s
}

func compiler_subset_fail(compiler_state initial, string feature) compiler_state {
    return compiler_fail(initial, "unsupported in no-GC compiler subset: " + feature)
}

func compiler_unsupported_token_message(string token) string {
    if token == "use" || token == "import" { return "imports and multi-package resolution" }
    if token == "enum" { return "enum declarations" }
    if token == "trait" || token == "interface" { return "traits and interfaces" }
    if token == "impl" { return "impl blocks" }
    if token == "defer" { return "defer statements" }
    if token == "go" || token == "sroutine" { return "concurrency statements" }
    if token == "match" || token == "switch" { return "match/switch statements" }
    if token == "map" { return "map values" }
    if token == "auto" { return "auto type declarations" }
    if token == "struct" { return "only two-field owned box structs are currently supported" }
    return ""
}

func compiler_next(compiler_state initial) compiler_state {
    s := initial
    if s.error != "" { return s }
    int n = len(s.source)
    for s.pos < n {
        string c = __host_char_at(s.source, s.pos)
        string d = ""
        if s.pos + 1 < n { d = __host_char_at(s.source, s.pos + 1) }
        if c == " " || c == "\t" || c == "\r" || c == "\n" {
            if c == "\n" { s.line = s.line + 1 }
            s.pos = s.pos + 1
        } else if c == "/" && d == "/" {
            for s.pos < n && __host_char_at(s.source, s.pos) != "\n" { s.pos = s.pos + 1 }
        } else if c == "/" && d == "*" {
            s.pos = s.pos + 2
            int nesting = 1
            for s.pos < n && nesting > 0 {
                c = __host_char_at(s.source, s.pos)
                d = ""
                if s.pos + 1 < n { d = __host_char_at(s.source, s.pos + 1) }
                if c == "/" && d == "*" { nesting = nesting + 1; s.pos = s.pos + 2 }
                else if c == "*" && d == "/" { nesting = nesting - 1; s.pos = s.pos + 2 }
                else { if c == "\n" { s.line = s.line + 1 } s.pos = s.pos + 1 }
            }
            if nesting != 0 { return compiler_fail(s, "unterminated comment") }
        } else { break }
    }
    if s.pos >= n { s.token = ""; return s }
    int start = s.pos
    string c = __host_char_at(s.source, s.pos)
    s.pos = s.pos + 1
    if c == "\"" {
        bool escaped = false
        for s.pos < n {
            string next_char = __host_char_at(s.source, s.pos)
            s.pos = s.pos + 1
            if escaped {
                escaped = false
            } else if next_char == "\\" {
                escaped = true
            } else if next_char == "\"" {
                break
            } else if next_char == "\n" {
                return compiler_fail(s, "unterminated string literal")
            }
        }
        if __host_char_at(s.source, s.pos - 1) != "\"" { return compiler_fail(s, "unterminated string literal") }
    } else if compiler_alpha(c) || compiler_digit(c) {
        for s.pos < n {
            string next_char = __host_char_at(s.source, s.pos)
            if !compiler_alpha(next_char) && !compiler_digit(next_char) { break }
            s.pos = s.pos + 1
        }
    } else {
        string pair = c
        if s.pos < n { pair = pair + __host_char_at(s.source, s.pos) }
        if pair == ":=" || pair == "==" || pair == "!=" || pair == "<=" || pair == ">=" || pair == "&&" || pair == "||" {
            s.pos = s.pos + 1
        } else if c != "(" && c != ")" && c != "{" && c != "}" && c != "[" && c != "]" && c != ";" && c != "," && c != "." && c != "+" && c != "-" && c != "*" && c != "/" && c != "%" && c != "&" && c != "=" && c != "!" && c != "<" && c != ">" {
            return compiler_fail(s, "unsupported token: " + c)
        }
    }
    s.token = "" + __host_slice(s.source, start, s.pos)
    return s
}

func compiler_expect(compiler_state initial, string token) compiler_state {
    s := initial
    if s.token != token { return compiler_fail(s, "expected '" + token + "', found '" + s.token + "'") }
    return compiler_next(s)
}

func compiler_optional_semicolon(compiler_state initial) compiler_state {
    s := initial
    if s.token == ";" { return compiler_next(s) }
    return s
}

func compiler_is_string_literal(string token) bool {
    return len(token) >= 2 && __host_char_at(token, 0) == "\""
}

func compiler_is_struct_type(string token) bool {
    return compiler_ident(token) && __host_char_at(token, 0) >= "A" && __host_char_at(token, 0) <= "Z"
}

func compiler_type_kind(string token) int {
    if token == "int" { return 1 }
    if token == "bool" { return 1 }
    if token == "box" { return 2 }
    if token == "ref" { return 3 }
    if token == "mutref" { return 4 }
    if token == "pair" { return 5 }
    if token == "slice" { return 9 }
    if token == "mutslice" { return 16 }
    if token == "string" { return 17 }
    return 0
}

func compiler_struct_c_name(compiler_state initial, int struct_id) string {
    s := initial
    "S_" + s.struct_names[struct_id]
}

func compiler_c_type_for_kind(compiler_state initial, int kind, int struct_id) string {
    s := initial
    if kind == 2 || kind == 4 { return "int64_t *" }
    if kind == 5 {
        if struct_id >= 0 { return compiler_struct_c_name(s, struct_id) + " *" }
        return "compiler_pair *"
    }
    if kind == 9 { return "compiler_slice *" }
    if kind == 15 { return "const int64_t *" }
    if kind == 16 { return "int64_t *" }
    if kind == 7 { return "const int64_t *" }
    if kind == 8 { return "int64_t *" }
    if kind == 3 { return "const int64_t *" }
    if kind == 18 { return "const void *" }
    if kind == 19 { return "void *" }
    if kind == 20 { return compiler_struct_c_name(s, struct_id) + " *" }
    if kind == 17 { return "const char *" }
    "int64_t "
}

func compiler_is_borrow_kind(int kind) bool {
    if kind == 3 || kind == 4 { return true }
    if kind == 18 || kind == 19 { return true }
    return false
}

func compiler_is_mutable_borrow_kind(int kind) bool {
    if kind == 4 || kind == 19 { return true }
    return false
}

func compiler_is_struct_access_kind(int kind) bool {
    return kind == 5 || kind == 20
}

func compiler_drop_field_code(compiler_state initial, string target, int kind, int struct_id) string {
    s := initial
    if kind == 2 { return "if (" + target + " != NULL) { compiler_drop(&" + target + "); }\n" }
    if kind == 5 {
        if struct_id >= 0 { return "if (" + target + " != NULL) { compiler_drop_owned_" + s.struct_names[struct_id] + "(&" + target + "); }\n" }
        return "if (" + target + " != NULL) { compiler_pair_drop(&" + target + "); }\n"
    }
    if kind == 9 { return "if (" + target + " != NULL) { compiler_slice_drop(&" + target + "); }\n" }
    ""
}

func compiler_find_struct(compiler_state initial, string name) int {
    s := initial
    int i = s.struct_count - 1
    for i >= 0 {
        if s.struct_names[i] == name { return i }
        i = i - 1
    }
    return -1
}

func compiler_parse_struct_decl(compiler_state initial) compiler_state {
    s := initial
    s = compiler_expect(s, "struct")
    if !compiler_is_struct_type(s.token) { return compiler_subset_fail(s, "struct names must be exported") }
    string struct_name = s.token
    if compiler_find_struct(s, struct_name) >= 0 { return compiler_fail(s, "duplicate struct: " + struct_name) }
    if s.struct_count >= 8 { return compiler_fail(s, "too many structs") }
    int struct_id = s.struct_count
    int field_start = s.function_param_total
    int field_count = 0
    string typedef_code = "typedef struct S_" + struct_name + " {\n"
    string make_params = ""
    string make_args = ""
    string make_body = ""
    string fields_drop = ""
    s = compiler_next(s)
    s = compiler_expect(s, "{")
    for s.token != "}" && s.token != "" {
        if !compiler_ident(s.token) { return compiler_subset_fail(s, "struct fields must be named") }
        field_name := s.token
        duplicate := false
        scan := 0
        for scan < field_count {
            if s.struct_field_names[field_start + scan] == field_name { duplicate = true }
            scan = scan + 1
        }
        if duplicate { return compiler_subset_fail(s, "struct fields must have distinct names") }
        s = compiler_next(s)
        field_kind := compiler_type_kind(s.token)
        field_struct := -1
        if field_kind == 0 && compiler_is_struct_type(s.token) {
            field_kind = 5
            field_struct = compiler_find_struct(s, s.token)
            if field_struct < 0 { return compiler_fail(s, "unknown struct field type: " + s.token) }
        }
        if field_kind == 0 { return compiler_subset_fail(s, "struct field type is not supported") }
        if field_count >= 8 { return compiler_fail(s, "too many struct fields") }
        index := field_start + field_count
        s.struct_field_names[index] = field_name
        s.struct_field_kinds[index] = field_kind
        s.struct_field_structs[index] = field_struct
        ctype := compiler_c_type_for_kind(s, field_kind, field_struct)
        typedef_code = typedef_code + "    " + ctype + field_name + ";\n"
        if field_count > 0 { make_params = make_params + ", "; make_args = make_args + "," }
        make_params = make_params + ctype + "p" + compiler_number(field_count)
        make_body = make_body + "    value->" + field_name + " = p" + compiler_number(field_count) + ";\n"
        make_args = make_args + "p" + compiler_number(field_count)
        drop_code := compiler_drop_field_code(s, "value->" + field_name, field_kind, field_struct)
        if drop_code != "" { fields_drop = drop_code + fields_drop }
        field_count = field_count + 1
        s = compiler_next(s)
        s = compiler_optional_semicolon(s)
    }
    if field_count == 0 { return compiler_subset_fail(s, "structs require at least one field") }
    s = compiler_expect(s, "}")
    typedef_code = typedef_code + "} S_" + struct_name + ";\n"
    fields_drop = "static inline __attribute__((unused)) void compiler_drop_fields_" + struct_name + "(S_" + struct_name + " *value) {\n" + fields_drop + "}\n"
    s.code = s.code + typedef_code
    s.code = s.code + "static void compiler_drop_user_" + struct_name + "(S_" + struct_name + " *value);\n"
    s.code = s.code + "static inline __attribute__((unused)) S_" + struct_name + " *compiler_make_" + struct_name + "(" + make_params + ") {\n"
    s.code = s.code + "    S_" + struct_name + " *value = (S_" + struct_name + " *)malloc(sizeof(*value));\n"
    s.code = s.code + "    if (!value) compiler_trap(\"allocation failed\");\n"
    s.code = s.code + make_body
    s.code = s.code + "#ifdef S_COMPILER_CHECK_ALLOCATIONS\n    ++compiler_objects;\n#endif\n"
    s.code = s.code + "    return value;\n}\n"
    s.code = s.code + fields_drop
    s.code = s.code + "static inline __attribute__((unused)) void compiler_drop_owned_" + struct_name + "(S_" + struct_name + " **owner) {\n"
    s.code = s.code + "    if (*owner) { compiler_drop_user_" + struct_name + "(*owner); compiler_drop_fields_" + struct_name + "(*owner); free(*owner); *owner = NULL;\n"
    s.code = s.code + "#ifdef S_COMPILER_CHECK_ALLOCATIONS\n    --compiler_objects;\n#endif\n"
    s.code = s.code + "    }\n}\n"
    s.code = s.code + "static inline __attribute__((unused)) S_" + struct_name + " *compiler_move_" + struct_name + "(S_" + struct_name + " **source) {\n"
    s.code = s.code + "    S_" + struct_name + " *value = *source;\n"
    s.code = s.code + "    *source = NULL;\n"
    s.code = s.code + "    return value;\n}\n"
    s.struct_names[struct_id] = struct_name
    s.struct_field_starts[struct_id] = field_start
    s.struct_field_counts[struct_id] = field_count
    if field_count >= 1 { s.struct_field_lefts[struct_id] = s.struct_field_names[field_start]; s.struct_field_left_kinds[struct_id] = s.struct_field_kinds[field_start] }
    if field_count >= 2 { s.struct_field_rights[struct_id] = s.struct_field_names[field_start + 1]; s.struct_field_right_kinds[struct_id] = s.struct_field_kinds[field_start + 1] }
    s.struct_count = s.struct_count + 1
    s.function_param_total = s.function_param_total + field_count
    return compiler_optional_semicolon(s)
}

func compiler_find(compiler_state initial, string name) int {
    s := initial
    int i = s.count - 1
    for i >= 0 {
        if s.names[i] == name { return i }
        i = i - 1
    }
    return -1
}

func compiler_var(int slot) string { return "s_v" + compiler_number(slot) }

func compiler_field_name(int field) string {
    if field == 0 { return "left" }
    return "right"
}

func compiler_field_index(compiler_state initial, int struct_id, string field_name) int {
    s := initial
    if struct_id >= 0 {
        start := s.struct_field_starts[struct_id]
        count := s.struct_field_counts[struct_id]
        i := 0
        for i < count {
            if field_name == s.struct_field_names[start + i] { return i }
            i = i + 1
        }
        return -1
    }
    if field_name == "left" { return 0 }
    if field_name == "right" { return 1 }
    return -1
}

func compiler_struct_field_name(compiler_state initial, int struct_id, int field) string {
    s := initial
    if struct_id >= 0 { return s.struct_field_names[s.struct_field_starts[struct_id] + field] }
    compiler_field_name(field)
}

func compiler_struct_field_kind(compiler_state initial, int struct_id, int field) int {
    s := initial
    if struct_id >= 0 { return s.struct_field_kinds[s.struct_field_starts[struct_id] + field] }
    2
}

func compiler_struct_field_struct(compiler_state initial, int struct_id, int field) int {
    s := initial
    if struct_id >= 0 { return s.struct_field_structs[s.struct_field_starts[struct_id] + field] }
    -1
}

func compiler_field_live(compiler_state initial, int slot, int field) int {
    s := initial
    idx := slot * 8 + field
    if slot >= 0 && slot < len(s.names) && field >= 0 && field < 8 && idx < len(s.field_state) {
        return s.field_state[idx]
    }
    return 1
}

func compiler_set_field_moved(compiler_state initial, int slot, int field) compiler_state {
    s := initial
    idx := slot * 8 + field
    if slot >= 0 && slot < len(s.names) && field >= 0 && field < 8 && idx < len(s.field_state) {
        s.field_state[idx] = 0
    }
    return s
}

func compiler_nested_field_index(int slot, int parent_field, int field) int {
    return slot * 64 + parent_field * 8 + field
}

func compiler_nested_field_live(compiler_state initial, int slot, int parent_field, int field) int {
    s := initial
    idx := compiler_nested_field_index(slot, parent_field, field)
    if slot >= 0 && parent_field >= 0 && parent_field < 8 && field >= 0 && field < 8 && idx < len(s.nested_field_state) {
        return s.nested_field_state[idx]
    }
    return 1
}

func compiler_set_nested_field_moved(compiler_state initial, int slot, int parent_field, int field) compiler_state {
    s := initial
    idx := compiler_nested_field_index(slot, parent_field, field)
    if slot >= 0 && parent_field >= 0 && parent_field < 8 && field >= 0 && field < 8 && idx < len(s.nested_field_state) {
        s.nested_field_state[idx] = 0
    }
    return s
}

func compiler_clear_nested_field_state(compiler_state initial, int slot, int parent_field) compiler_state {
    s := initial
    field := 0
    for field < 8 {
        idx := compiler_nested_field_index(slot, parent_field, field)
        if slot >= 0 && parent_field >= 0 && parent_field < 8 && idx < len(s.nested_field_state) {
            s.nested_field_state[idx] = 1
        }
        field = field + 1
    }
    return s
}

func compiler_merge_ownership_state(int left, int right) int {
    if left == right { return left }
    return 2
}

func compiler_field_borrow_count(compiler_state initial, int slot, int field) int {
    s := initial
    idx := slot * 8 + field
    if slot >= 0 && slot < len(s.names) && field >= 0 && field < 8 && idx < len(s.field_borrow_state) {
        return s.field_borrow_state[idx]
    }
    return 0
}

func compiler_field_has_borrow(compiler_state initial, int slot, int field) bool {
    s := initial
    if field >= 0 { return compiler_field_borrow_count(s, slot, field) > 0 }
    scan := 0
    for scan < 8 {
        if compiler_field_borrow_count(s, slot, scan) > 0 { return true }
        scan = scan + 1
    }
    return false
}

func compiler_add_field_borrow(compiler_state initial, int slot, int field) compiler_state {
    s := initial
    idx := slot * 8 + field
    if slot >= 0 && slot < len(s.names) && field >= 0 && field < 8 && idx < len(s.field_borrow_state) {
        s.field_borrow_state[idx] = s.field_borrow_state[idx] + 1
    }
    return s
}

func compiler_drop_field_borrow(compiler_state initial, int slot, int field) compiler_state {
    s := initial
    idx := slot * 8 + field
    if slot >= 0 && slot < len(s.names) && field >= 0 && field < 8 && idx < len(s.field_borrow_state) && s.field_borrow_state[idx] > 0 {
        s.field_borrow_state[idx] = s.field_borrow_state[idx] - 1
    }
    return s
}

func compiler_nested_field_borrow_count(compiler_state initial, int slot, int parent_field, int field) int {
    s := initial
    idx := compiler_nested_field_index(slot, parent_field, field)
    if slot >= 0 && parent_field >= 0 && parent_field < 8 && field >= 0 && field < 8 && idx < len(s.nested_field_borrow_state) {
        return s.nested_field_borrow_state[idx]
    }
    return 0
}

func compiler_nested_field_has_borrow(compiler_state initial, int slot, int parent_field, int field) bool {
    s := initial
    if field >= 0 { return compiler_nested_field_borrow_count(s, slot, parent_field, field) > 0 }
    scan := 0
    for scan < 8 {
        if compiler_nested_field_borrow_count(s, slot, parent_field, scan) > 0 { return true }
        scan = scan + 1
    }
    return false
}

func compiler_add_nested_field_borrow(compiler_state initial, int slot, int parent_field, int field) compiler_state {
    s := initial
    idx := compiler_nested_field_index(slot, parent_field, field)
    if slot >= 0 && parent_field >= 0 && parent_field < 8 && field >= 0 && field < 8 && idx < len(s.nested_field_borrow_state) {
        s.nested_field_borrow_state[idx] = s.nested_field_borrow_state[idx] + 1
    }
    return s
}

func compiler_drop_nested_field_borrow(compiler_state initial, int slot, int parent_field, int field) compiler_state {
    s := initial
    idx := compiler_nested_field_index(slot, parent_field, field)
    if slot >= 0 && parent_field >= 0 && parent_field < 8 && field >= 0 && field < 8 && idx < len(s.nested_field_borrow_state) && s.nested_field_borrow_state[idx] > 0 {
        s.nested_field_borrow_state[idx] = s.nested_field_borrow_state[idx] - 1
    }
    return s
}

func compiler_field_unavailable_message(int state) string {
    if state == 0 { return "use of moved owned struct field" }
    if state == 2 { return "use of conditionally moved owned struct field" }
    return ""
}

func compiler_has_moved_field(compiler_state initial, int slot) bool {
    s := initial
    if slot < 0 || slot >= len(s.names) { return false }
    if s.kinds[slot] != 5 { return false }
    struct_id := s.struct_ids[slot]
    if struct_id < 0 { return false }
    field_count := s.struct_field_counts[struct_id]
    field := 0
    for field < field_count {
        if compiler_field_live(s, slot, field) != 1 { return true }
        if compiler_has_moved_nested_field(s, slot, field) { return true }
        field = field + 1
    }
    return false
}

func compiler_has_moved_nested_field(compiler_state initial, int slot, int parent_field) bool {
    s := initial
    field := 0
    for field < 8 {
        if compiler_nested_field_live(s, slot, parent_field, field) != 1 { return true }
        field = field + 1
    }
    return false
}

func compiler_merge_field_states(compiler_state initial, compiler_state yes, compiler_state no, int limit) compiler_state {
    merged := no
    slot := 0
    for slot < limit {
        field := 0
        for field < 8 {
            idx := slot * 8 + field
            if idx < len(merged.field_state) {
                if yes.terminated == 0 && no.terminated != 0 {
                    merged.field_state[idx] = yes.field_state[idx]
                } else if yes.terminated == 0 && no.terminated == 0 {
                    merged.field_state[idx] = compiler_merge_ownership_state(yes.field_state[idx], no.field_state[idx])
                }
            }
            field = field + 1
        }
        slot = slot + 1
    }
    return merged
}

func compiler_merge_nested_field_states(compiler_state initial, compiler_state yes, compiler_state no, int limit) compiler_state {
    merged := no
    slot := 0
    for slot < limit {
        parent_field := 0
        for parent_field < 8 {
            field := 0
            for field < 8 {
                idx := compiler_nested_field_index(slot, parent_field, field)
                if idx < len(merged.nested_field_state) {
                    if yes.terminated == 0 && no.terminated != 0 {
                        merged.nested_field_state[idx] = yes.nested_field_state[idx]
                    } else if yes.terminated == 0 && no.terminated == 0 {
                        merged.nested_field_state[idx] = compiler_merge_ownership_state(yes.nested_field_state[idx], no.nested_field_state[idx])
                    }
                }
                field = field + 1
            }
            parent_field = parent_field + 1
        }
        slot = slot + 1
    }
    return merged
}

func compiler_merge_field_borrow_states(compiler_state initial, compiler_state yes, compiler_state no, int limit) compiler_state {
    merged := no
    slot := 0
    for slot < limit {
        field := 0
        for field < 8 {
            idx := slot * 8 + field
            if idx < len(merged.field_borrow_state) {
                if yes.terminated == 0 && no.terminated != 0 {
                    merged.field_borrow_state[idx] = yes.field_borrow_state[idx]
                } else if yes.terminated == 0 && no.terminated == 0 {
                    if yes.field_borrow_state[idx] > 0 || no.field_borrow_state[idx] > 0 {
                        merged.field_borrow_state[idx] = 1
                    } else {
                        merged.field_borrow_state[idx] = 0
                    }
                }
            }
            field = field + 1
        }
        slot = slot + 1
    }
    return merged
}

func compiler_merge_nested_field_borrow_states(compiler_state initial, compiler_state yes, compiler_state no, int limit) compiler_state {
    merged := no
    slot := 0
    for slot < limit {
        parent_field := 0
        for parent_field < 8 {
            field := 0
            for field < 8 {
                idx := compiler_nested_field_index(slot, parent_field, field)
                if idx < len(merged.nested_field_borrow_state) {
                    if yes.terminated == 0 && no.terminated != 0 {
                        merged.nested_field_borrow_state[idx] = yes.nested_field_borrow_state[idx]
                    } else if yes.terminated == 0 && no.terminated == 0 {
                        if yes.nested_field_borrow_state[idx] > 0 || no.nested_field_borrow_state[idx] > 0 {
                            merged.nested_field_borrow_state[idx] = 1
                        } else {
                            merged.nested_field_borrow_state[idx] = 0
                        }
                    }
                }
                field = field + 1
            }
            parent_field = parent_field + 1
        }
        slot = slot + 1
    }
    return merged
}

func compiler_move_field_expr(compiler_state initial, int origin, int field, int kind, int struct_id) string {
    s := initial
    if s.struct_ids[origin] < 0 { return "compiler_pair_move_field(" + compiler_var(origin) + "," + compiler_number(field) + ")" }
    target := compiler_var(origin) + "->" + compiler_struct_field_name(s, s.struct_ids[origin], field)
    if kind == 2 { return "compiler_move(&" + target + ")" }
    if kind == 5 { return "compiler_move_" + s.struct_names[struct_id] + "(&" + target + ")" }
    if kind == 9 { return "compiler_slice_move(&" + target + ")" }
    return target
}

func compiler_move_nested_field_expr(compiler_state initial, int origin, int parent_field, int field, int kind, int struct_id) string {
    s := initial
    parent_name := compiler_struct_field_name(s, s.struct_ids[origin], parent_field)
    parent_struct := compiler_struct_field_struct(s, s.struct_ids[origin], parent_field)
    target := compiler_var(origin) + "->" + parent_name + "->" + compiler_struct_field_name(s, parent_struct, field)
    if kind == 2 { return "compiler_move(&" + target + ")" }
    if kind == 5 { return "compiler_move_" + s.struct_names[struct_id] + "(&" + target + ")" }
    if kind == 9 { return "compiler_slice_move(&" + target + ")" }
    return target
}

func compiler_move_value_field_expr(compiler_state initial) compiler_state {
    s := initial
    origin := s.value_slot
    if s.value_parent_field >= 0 {
        if compiler_nested_field_has_borrow(s, origin, s.value_parent_field, s.value_field) { return compiler_fail(s, "cannot move borrowed nested struct field") }
        if compiler_conflict_at(s, origin, s.value_parent_field, true) { return compiler_fail(s, "cannot move borrowed pair field") }
        s = compiler_set_nested_field_moved(s, origin, s.value_parent_field, s.value_field)
        if s.error != "" { return s }
        s.value = compiler_move_nested_field_expr(s, origin, s.value_parent_field, s.value_field, s.value_kind, s.value_struct_id)
        return s
    }
    if compiler_conflict_at(s, origin, s.value_field, true) { return compiler_fail(s, "cannot move borrowed pair field") }
    if compiler_nested_field_has_borrow(s, origin, s.value_field, -1) { return compiler_fail(s, "cannot move borrowed nested struct field") }
    if s.value_kind == 5 && compiler_has_moved_nested_field(s, origin, s.value_field) { return compiler_fail(s, "cannot move partially moved struct field") }
    s = compiler_set_field_moved(s, origin, s.value_field)
    s = compiler_clear_nested_field_state(s, origin, s.value_field)
    if s.error != "" { return s }
    s.value = compiler_move_field_expr(s, origin, s.value_field, s.value_kind, s.value_struct_id)
    return s
}

func compiler_array_length(compiler_state initial, int slot) string {
    s := initial
    if s.kinds[slot] == 9 { return compiler_var(slot) + "->len" }
    if s.kinds[slot] == 15 || s.kinds[slot] == 16 { return compiler_var(slot) + "_len" }
    if s.array_lengths[slot] >= 0 { return compiler_number(s.array_lengths[slot]) }
    return compiler_var(slot) + "_len"
}

func compiler_find_func(compiler_state initial, string name) int {
    s := initial
    int i = s.function_count - 1
    for i >= 0 {
        if s.function_names[i] == name { return i }
        i = i - 1
    }
    return -1
}

func compiler_generic_instance_name(string generic_name, int kind) string {
    if kind == 1 { return generic_name + "__mono_int" }
    if kind == 2 { return generic_name + "__mono_box" }
    return generic_name + "__mono_unknown"
}

func compiler_explicit_type_arg_kind(string token) int {
    if token == "int" { return 1 }
    if token == "box" { return 2 }
    return 0
}

func compiler_find_method(compiler_state initial, int struct_id, string name) int {
    s := initial
    int i = s.method_count - 1
    for i >= 0 {
        if s.method_structs[i] == struct_id && s.method_names[i] == name { return i }
        i = i - 1
    }
    return -1
}

func compiler_method_c_name(compiler_state initial, int method_index) string {
    s := initial
    return "method_" + s.struct_names[s.method_structs[method_index]] + "_" + s.method_names[method_index]
}

func compiler_conflict_at(compiler_state initial, int owner, int field, bool exclusive) bool {
    s := initial
    int i = 0
    for i < s.count {
        bool same_field = field < 0 || s.loan_fields[i] < 0 || s.loan_fields[i] == field
        bool mutable_loan = compiler_is_mutable_borrow_kind(s.kinds[i]) || s.kinds[i] == 11
        bool shared_loan = s.kinds[i] == 3 || s.kinds[i] == 10 || s.kinds[i] == 18
        if s.live[i] != 0 && s.roots[i] == owner && same_field && (mutable_loan || (exclusive && shared_loan)) { return true }
        i = i + 1
    }
    if exclusive && compiler_field_has_borrow(s, owner, field) { return true }
    return false
}

func compiler_conflict(compiler_state initial, int owner, bool exclusive) bool {
    return compiler_conflict_at(initial, owner, -1, exclusive)
}

func compiler_child_conflict(compiler_state initial, int parent, bool exclusive) bool {
    s := initial
    int i = 0
    for i < s.count {
        if s.live[i] != 0 && s.parents[i] == parent && (compiler_is_mutable_borrow_kind(s.kinds[i]) || (exclusive && (s.kinds[i] == 3 || s.kinds[i] == 18))) { return true }
        i = i + 1
    }
    return false
}

func compiler_available(compiler_state initial, int slot) compiler_state {
    s := initial
    if slot < 0 { return compiler_fail(s, "unknown variable") }
    if s.live[slot] != 1 { return compiler_fail(s, "use of moved, dropped or conditionally initialized value: " + s.names[slot]) }
    return s
}

func compiler_consume(compiler_state initial, int slot) compiler_state {
    s := initial
    s = compiler_available(s, slot)
    if s.error != "" { return s }
    if compiler_conflict(s, slot, true) { return compiler_fail(s, "cannot move or drop borrowed owner: " + s.names[slot]) }
    if compiler_has_moved_field(s, slot) { return compiler_fail(s, "cannot move partially moved struct: " + s.names[slot]) }
    if s.loop_floor >= 0 && slot < s.loop_floor { return compiler_fail(s, "cannot consume an outer owner inside a loop") }
    s.live[slot] = 0
    return s
}

func compiler_cleanup(compiler_state initial, int floor) string {
    s := initial
    string code = ""
    int i = s.count - 1
    for i >= floor {
        if s.live[i] != 0 { code = code + compiler_drop_owner(s, i) }
        i = i - 1
    }
    return code
}

func compiler_drop_owner(compiler_state initial, int slot) string {
    s := initial
    if s.kinds[slot] == 2 { return "compiler_drop(&" + compiler_var(slot) + ");\n" }
    if s.kinds[slot] == 5 {
        struct_id := s.struct_ids[slot]
        if struct_id >= 0 {
            return "compiler_drop_owned_" + s.struct_names[struct_id] + "(&" + compiler_var(slot) + ");\n"
        }
        return "compiler_pair_drop(&" + compiler_var(slot) + ");\n"
    }
    if s.kinds[slot] == 9 { return "compiler_slice_drop(&" + compiler_var(slot) + ");\n" }
    ""
}

func compiler_overwrite_old_owner(compiler_state initial, int slot) string {
    s := initial
    if s.live[slot] == 0 { return "" }
    compiler_drop_owner(s, slot)
}

func compiler_drop_field_owner_code(compiler_state initial, int slot, int field, int kind, int struct_id) string {
    s := initial
    target := compiler_var(slot) + "->" + compiler_struct_field_name(s, s.struct_ids[slot], field)
    if compiler_field_live(s, slot, field) != 1 { return "" }
    return compiler_drop_field_code(s, target, kind, struct_id)
}

func compiler_precedence(string op) int {
    if op == "||" { return 1 }
    if op == "&&" { return 2 }
    if op == "==" || op == "!=" { return 3 }
    if op == "<" || op == ">" || op == "<=" || op == ">=" { return 4 }
    if op == "+" || op == "-" { return 5 }
    if op == "*" || op == "/" || op == "%" { return 6 }
    return 0
}

func compiler_atom(compiler_state initial) compiler_state {
    s := initial
    if s.error != "" { return s }
    s.expr_depth = s.expr_depth + 1
    if s.expr_depth > 64 { return compiler_fail(s, "expression nesting limit exceeded") }
    s = compiler_atom_inner(s)
    s.expr_depth = s.expr_depth - 1
    return s
}

func compiler_atom_inner(compiler_state initial) compiler_state {
    s := initial
    string t = s.token
    s.value_slot = -1
    s.value_parent = -1
    s.value_field = -1
    s.value_parent_field = -1
    s.value_array_length = 0
    s.value_struct_id = -1
    s.new_borrow = false
    if t == "(" {
        s = compiler_expression(compiler_next(s), 1)
        return compiler_expect(s, ")")
    }
    if t == "[" {
        s = compiler_next(s)
        int count = 0
        string values = "{"
        while s.token != "]" && s.token != "" {
            if count > 0 { s = compiler_expect(s, ",") }
            s = compiler_expression(s, 1)
            if s.value_kind != 1 { return compiler_fail(s, "array elements require integers") }
            if count > 0 { values = values + "," }
            values = values + s.value
            count = count + 1
            if count > 64 { return compiler_fail(s, "array literal exceeds 64 elements") }
        }
        if count == 0 { return compiler_fail(s, "array literal cannot be empty") }
        s = compiler_expect(s, "]")
        s.value = values + "}"
        s.value_kind = 6
        s.value_array_length = count
        s.value_slot = -1
        return s
    }
    if t == "-" || t == "!" {
        s = compiler_atom(compiler_next(s))
        if s.value_kind != 1 { return compiler_fail(s, "unary operator requires an integer") }
        if t == "-" { s.value = "compiler_sub(0," + s.value + ")" }
        else { s.value = "(!(" + s.value + "))" }
        s.value_slot = -1
        return s
    }
    if t == "&" {
        s = compiler_next(s)
        int kind = 3
        if s.token == "mut" { kind = 4; s = compiler_next(s) }
        bool reborrow = s.token == "*"
        if reborrow { s = compiler_next(s) }
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        int field = -1
        int parent_field = -1
        string field_path = ""
        if !reborrow {
            s = compiler_next(s)
            if s.token == "." {
                s = compiler_next(s)
                field = compiler_field_index(s, s.struct_ids[slot], s.token)
                if field < 0 { return compiler_fail(s, "unknown owned struct field") }
                if s.kinds[slot] != 5 { return compiler_fail(s, "field borrow requires a pair") }
                field_state := compiler_field_live(s, slot, field)
                field_error := compiler_field_unavailable_message(field_state)
                if field_error != "" { return compiler_fail(s, field_error) }
                int field_kind = compiler_struct_field_kind(s, s.struct_ids[slot], field)
                if field_kind != 2 {
                    if kind == 4 { kind = 19 }
                    else { kind = 18 }
                }
                field_path = compiler_struct_field_name(s, s.struct_ids[slot], field)
                s = compiler_next(s)
                if s.token == "." {
                    if field_kind != 5 { return compiler_fail(s, "nested field borrow requires a named struct field") }
                    parent_field = field
                    parent_struct := compiler_struct_field_struct(s, s.struct_ids[slot], field)
                    s = compiler_next(s)
                    field = compiler_field_index(s, parent_struct, s.token)
                    if field < 0 { return compiler_fail(s, "unknown nested owned struct field") }
                    nested_state := compiler_nested_field_live(s, slot, parent_field, field)
                    nested_error := compiler_field_unavailable_message(nested_state)
                    if nested_error != "" { return compiler_fail(s, nested_error) }
                    nested_kind := compiler_struct_field_kind(s, parent_struct, field)
                    if nested_kind != 2 {
                        if kind == 4 { kind = 19 }
                        else { kind = 18 }
                    }
                    field_path = field_path + "->" + compiler_struct_field_name(s, parent_struct, field)
                }
            }
        }
        int root = slot
        if reborrow {
            if s.kinds[slot] < 3 { return compiler_fail(s, "reborrow requires a reference") }
            if kind == 4 && s.kinds[slot] == 3 { return compiler_fail(s, "cannot mutably reborrow a shared reference") }
            if compiler_child_conflict(s, slot, kind == 4) { return compiler_fail(s, "conflicting reborrow: " + s.names[slot]) }
            root = s.roots[slot]
            s.value_parent = slot
        } else {
            if field < 0 && s.kinds[slot] != 2 { return compiler_fail(s, "borrow requires an owned box or pair field; use &*reference to reborrow") }
            if field >= 0 {
                if parent_field >= 0 {
                    if compiler_conflict_at(s, slot, parent_field, kind == 4) { return compiler_fail(s, "conflicting field borrow: " + s.names[slot]) }
                    if compiler_nested_field_has_borrow(s, slot, parent_field, field) { return compiler_fail(s, "conflicting nested field borrow: " + s.names[slot]) }
                } else if compiler_conflict_at(s, slot, field, kind == 4) { return compiler_fail(s, "conflicting field borrow: " + s.names[slot]) }
            } else if compiler_conflict(s, slot, kind == 4) { return compiler_fail(s, "conflicting borrow: " + s.names[slot]) }
        }
        if reborrow || parent_field >= 0 { s = compiler_next(s) }
        s.value = compiler_var(slot)
        if field >= 0 { s.value = compiler_var(slot) + "->" + field_path }
        if kind == 18 { s.value = "(const void *)" + s.value }
        if kind == 19 { s.value = "(void *)" + s.value }
        s.value_kind = kind
        s.value_slot = root
        s.value_field = field
        s.value_parent_field = parent_field
        s.new_borrow = true
        return s
    }
    if t == "*" {
        s = compiler_next(s)
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] != 2 && s.kinds[slot] != 3 && s.kinds[slot] != 4 && !compiler_is_struct_access_kind(s.kinds[slot]) { return compiler_fail(s, "dereference requires a box or integer reference") }
        int field = -1
        s = compiler_next(s)
        if s.token == "." {
            s = compiler_next(s)
            field = compiler_field_index(s, s.struct_ids[slot], s.token)
            if field < 0 { return compiler_fail(s, "invalid owned struct field dereference") }
            if !compiler_is_struct_access_kind(s.kinds[slot]) { return compiler_fail(s, "invalid pair field dereference") }
            if compiler_struct_field_kind(s, s.struct_ids[slot], field) != 2 { return compiler_fail(s, "field dereference requires an owned box field") }
            field_state := compiler_field_live(s, slot, field)
            field_error := compiler_field_unavailable_message(field_state)
            if field_error != "" { return compiler_fail(s, field_error) }
            if compiler_conflict_at(s, slot, field, false) { return compiler_fail(s, "cannot read pair field during a mutable borrow") }
            field_name := compiler_struct_field_name(s, s.struct_ids[slot], field)
            s.value = "(*" + compiler_var(slot) + "->" + field_name + ")"
            s = compiler_next(s)
        } else {
            if compiler_is_struct_access_kind(s.kinds[slot]) { return compiler_fail(s, "struct dereference requires an owned box field") }
            s.value = "(*" + compiler_var(slot) + ")"
        }
        if compiler_is_borrow_kind(s.kinds[slot]) && compiler_child_conflict(s, slot, false) { return compiler_fail(s, "cannot read reference during a mutable reborrow") }
        if s.kinds[slot] == 2 && compiler_conflict(s, slot, false) { return compiler_fail(s, "owner cannot be read during a mutable borrow") }
        s.value_kind = 1
        s.value_slot = -1
        return s
    }
    if t == "box" {
        s = compiler_expect(compiler_next(s), "(")
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "box requires an integer") }
        s = compiler_expect(s, ")")
        s.value = "compiler_box(" + s.value + ")"
        s.value_kind = 2
        s.value_slot = -1
        return s
    }
    if t == "len" {
        s = compiler_expect(compiler_next(s), "(")
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] != 6 && s.kinds[slot] != 7 && s.kinds[slot] != 8 && s.kinds[slot] != 9 && s.kinds[slot] != 15 && s.kinds[slot] != 16 { return compiler_fail(s, "len requires an integer array or slice") }
        s = compiler_expect(compiler_next(s), ")")
        s.value = "INT64_C(" + compiler_array_length(s, slot) + ")"
        if s.kinds[slot] == 9 { s.value = compiler_var(slot) + "->len" }
        if s.kinds[slot] == 15 || s.kinds[slot] == 16 { s.value = compiler_var(slot) + "_len" }
        else if s.array_lengths[slot] < 0 { s.value = compiler_var(slot) + "_len" }
        s.value_kind = 1
        s.value_slot = -1
        return s
    }
    if t == "slice" {
        s = compiler_expect(compiler_next(s), "(")
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] != 6 { return compiler_fail(s, "slice requires a fixed integer array") }
        int length = s.array_lengths[slot]
        s = compiler_expect(compiler_next(s), ")")
        s.value = "compiler_slice_from_array(" + compiler_var(slot) + "," + compiler_number(length) + ")"
        s.value_kind = 9
        s.value_slot = -1
        return s
    }
    if t == "pair" {
        int constructed_struct = -1
        s = compiler_expect(compiler_next(s), "(")
        s = compiler_expression(s, 1)
        if s.value_kind != 2 { return compiler_fail(s, "struct left field requires an owner") }
        string left = s.value
            if s.value_slot >= 0 {
                int origin = s.value_slot
                if s.value_field >= 0 {
                    s = compiler_move_value_field_expr(s)
                    if s.error != "" { return s }
                    left = s.value
                } else {
                s = compiler_consume(s, origin)
                left = "compiler_move(&" + compiler_var(origin) + ")"
            }
        }
        s = compiler_expect(s, ",")
        s = compiler_expression(s, 1)
        if s.value_kind != 2 { return compiler_fail(s, "struct right field requires an owner") }
        string right = s.value
            if s.value_slot >= 0 {
                int origin = s.value_slot
                if s.value_field >= 0 {
                    s = compiler_move_value_field_expr(s)
                    if s.error != "" { return s }
                    right = s.value
                } else {
                s = compiler_consume(s, origin)
                right = "compiler_move(&" + compiler_var(origin) + ")"
            }
        }
        s = compiler_expect(s, ")")
        s.value = "compiler_pair_make(" + left + "," + right + ")"
        s.value_kind = 5
        s.value_struct_id = constructed_struct
        s.value_slot = -1
        return s
    }
    if compiler_is_struct_type(t) {
        constructed_struct := compiler_find_struct(s, t)
        if constructed_struct < 0 { return compiler_fail(s, "unknown struct: " + t) }
        field_count := s.struct_field_counts[constructed_struct]
        field_start := s.struct_field_starts[constructed_struct]
        s = compiler_expect(compiler_next(s), "(")
        args := ""
        field := 0
        for field < field_count {
            if field > 0 { s = compiler_expect(s, ",") }
            s = compiler_expression(s, 1)
            expected := s.struct_field_kinds[field_start + field]
            expected_struct := s.struct_field_structs[field_start + field]
            if s.value_kind != expected { return compiler_fail(s, "struct field initializer type mismatch") }
            if expected == 5 && s.value_struct_id != expected_struct { return compiler_fail(s, "struct field initializer struct type mismatch") }
            argument := s.value
            if expected == 2 || expected == 5 || expected == 9 {
                if s.value_field >= 0 {
                    origin := s.value_slot
                    s = compiler_move_value_field_expr(s)
                    if s.error != "" { return s }
                    argument = s.value
                } else if s.value_slot >= 0 {
                    origin := s.value_slot
                    s = compiler_consume(s, origin)
                    if expected == 5 {
                        if s.value_struct_id >= 0 { argument = "compiler_move_" + s.struct_names[s.value_struct_id] + "(&" + compiler_var(origin) + ")" }
                        else { argument = "compiler_pair_move(&" + compiler_var(origin) + ")" }
                    } else if expected == 9 { argument = "compiler_slice_move(&" + compiler_var(origin) + ")" }
                    else { argument = "compiler_move(&" + compiler_var(origin) + ")" }
                }
            }
            if field > 0 { args = args + "," }
            args = args + argument
            field = field + 1
        }
        s = compiler_expect(s, ")")
        s.value = "compiler_make_" + t + "(" + args + ")"
        s.value_kind = 5
        s.value_struct_id = constructed_struct
        s.value_slot = -1
        return s
    }
    if t == "live_allocations" {
        s = compiler_expect(compiler_next(s), "(")
        s = compiler_expect(s, ")")
        s.value = "compiler_live()"
        s.value_kind = 1
        return s
    }
    if compiler_ident(t) {
        generic_call := compiler_next(s)
        if generic_call.token == "[" {
            generic_call = compiler_next(generic_call)
            type_kind := compiler_explicit_type_arg_kind(generic_call.token)
            if type_kind == 0 { return compiler_fail(s, "generic function type argument must be int or box in this subset") }
            instance_name := compiler_generic_instance_name(t, type_kind)
            function_index := compiler_find_func(generic_call, instance_name)
            if function_index < 0 { return compiler_fail(s, "unknown generic function instance: " + instance_name) }
            generic_call = compiler_expect(compiler_next(generic_call), "]")
            generic_call = compiler_expect(generic_call, "(")
            generic_call = compiler_expression(generic_call, 1)
            expected := generic_call.function_param_kinds[generic_call.function_starts[function_index]]
            if generic_call.value_kind != expected { return compiler_fail(generic_call, "generic function argument type mismatch") }
            argument := generic_call.value
            if expected == 2 {
                if generic_call.value_field >= 0 {
                    generic_call = compiler_move_value_field_expr(generic_call)
                    if generic_call.error != "" { return generic_call }
                    argument = generic_call.value
                } else if generic_call.value_slot >= 0 {
                    origin := generic_call.value_slot
                    generic_call = compiler_consume(generic_call, origin)
                    if generic_call.error != "" { return generic_call }
                    argument = "compiler_move(&" + compiler_var(origin) + ")"
                }
            }
            generic_call = compiler_expect(generic_call, ")")
            generic_call.value = instance_name + "(" + argument + ")"
            generic_call.value_kind = generic_call.function_returns[function_index]
            generic_call.value_slot = -1
            generic_call.value_struct_id = -1
            generic_call.new_borrow = false
            return generic_call
        }
    }
    if compiler_ident(t) && compiler_find_func(s, t) >= 0 {
        int function_index = compiler_find_func(s, t)
        s = compiler_expect(compiler_next(s), "(")
        string args = ""
        string evaluations = ""
        string call_id = compiler_number(s.pos)
        int arg = 0
        int loan_floor = s.count
        int returned_loan_slot = -1
        for s.error == "" && s.token != ")" && s.token != "" {
            if arg > 0 { s = compiler_expect(s, ",") }
            s = compiler_expression(s, 1)
            if s.value_kind < 1 || (s.value_kind > 9 && s.value_kind != 17) { return compiler_fail(s, "function arguments require integers, strings, owners, arrays, slices, pairs or references") }
            if arg >= s.function_counts[function_index] { return compiler_fail(s, "too many function arguments") }
            int expected = s.function_param_kinds[s.function_starts[function_index] + arg]
            if expected == 7 || expected == 8 {
                if s.value_kind != 6 && s.value_kind != 7 && s.value_kind != 8 { return compiler_fail(s, "function argument requires an integer array") }
            } else if expected == 15 || expected == 16 {
                if s.value_kind != 9 && s.value_kind != 15 && s.value_kind != 16 { return compiler_fail(s, "function argument requires a slice") }
            } else if s.value_kind != expected { return compiler_fail(s, "function argument type mismatch") }
            if expected == 5 && s.value_struct_id != s.function_param_structs[s.function_starts[function_index] + arg] { return compiler_fail(s, "function argument struct type mismatch") }
            string argument = s.value
            string argument_length = ""
            if expected == 7 || expected == 8 || expected == 15 || expected == 16 {
                if s.value_slot < 0 { return compiler_fail(s, "array argument requires a named array") }
                argument_length = compiler_array_length(s, s.value_slot)
                if expected == 15 || expected == 16 {
                    if s.value_kind == 9 { argument = compiler_var(s.value_slot) + "->data" }
                }
            }
            if expected >= 3 && expected <= 4 {
                int root = s.value_slot
                int parent = s.value_parent
                if !s.new_borrow {
                    parent = s.value_slot
                    root = s.roots[parent]
                    if compiler_child_conflict(s, parent, expected == 4) { return compiler_fail(s, "conflicting argument reborrow") }
                }
                if s.count >= len(s.names) { return compiler_fail(s, "argument loan capacity exceeded") }
                s.names[s.count] = ""
                s.kinds[s.count] = expected
                s.live[s.count] = 1
                s.roots[s.count] = root
                s.parents[s.count] = parent
                s.loan_fields[s.count] = -1
                s.loan_parent_fields[s.count] = -1
                if s.value_field >= 0 { s.loan_fields[s.count] = s.value_field }
                if s.value_parent_field >= 0 { s.loan_parent_fields[s.count] = s.value_parent_field }
                if s.function_returns[function_index] >= 3 && s.function_returns[function_index] <= 4 && arg == s.function_return_params[function_index] {
                    returned_loan_slot = s.count
                }
                s.count = s.count + 1
            }
            if expected == 7 || expected == 8 || expected == 15 || expected == 16 {
                if s.value_slot < 0 { return compiler_fail(s, "array argument requires a named array") }
                bool exclusive = expected == 8 || expected == 16
                if compiler_conflict(s, s.value_slot, exclusive) { return compiler_fail(s, "conflicting array argument borrow") }
                if s.count >= len(s.names) { return compiler_fail(s, "argument loan capacity exceeded") }
                s.names[s.count] = ""
                if exclusive { s.kinds[s.count] = 11 }
                else { s.kinds[s.count] = 10 }
                s.live[s.count] = 1
                s.roots[s.count] = s.value_slot
                s.parents[s.count] = -1
                s.loan_fields[s.count] = -1
                s.loan_parent_fields[s.count] = -1
                s.array_lengths[s.count] = 0
                s.count = s.count + 1
            }
            if expected == 2 || expected == 5 || expected == 9 {
                if s.value_field >= 0 {
                    int origin = s.value_slot
                    s = compiler_move_value_field_expr(s)
                    if s.error != "" { return s }
                    argument = s.value
                } else if s.value_slot >= 0 {
                    int origin = s.value_slot
                    s = compiler_consume(s, origin)
                    if expected == 5 {
                        if s.value_struct_id >= 0 { argument = "compiler_move_" + s.struct_names[s.value_struct_id] + "(&" + compiler_var(origin) + ")" }
                        else { argument = "compiler_pair_move(&" + compiler_var(origin) + ")" }
                    }
                    else if expected == 9 { argument = "compiler_slice_move(&" + compiler_var(origin) + ")" }
                    else { argument = "compiler_move(&" + compiler_var(origin) + ")" }
                }
            }
            string temporary = "s_arg" + call_id + "_" + compiler_number(arg)
            string argument_type = compiler_c_type_for_kind(s, expected, s.function_param_structs[s.function_starts[function_index] + arg])
            s.code = s.code + argument_type + temporary + ";\n"
            evaluations = evaluations + "(" + temporary + " = " + argument + "),"
            if arg > 0 { args = args + "," }
            args = args + temporary
            if expected == 7 || expected == 8 || expected == 15 || expected == 16 { args = args + "," + argument_length }
            arg = arg + 1
        }
        if arg != s.function_counts[function_index] { return compiler_fail(s, "wrong number of function arguments") }
        s = compiler_expect(s, ")")
        int returned_root = -1
        int returned_parent = -1
        if s.function_returns[function_index] >= 3 && s.function_returns[function_index] <= 4 {
            if returned_loan_slot < 0 || returned_loan_slot >= s.count { return compiler_fail(s, "reference return argument is unavailable") }
            returned_root = s.roots[returned_loan_slot]
            returned_parent = s.parents[returned_loan_slot]
        }
        s.count = loan_floor
        s.value = "(" + evaluations + s.function_names[function_index] + "(" + args + "))"
        s.value_kind = s.function_returns[function_index]
        s.value_struct_id = s.function_return_structs[function_index]
        if s.value_kind >= 3 && s.value_kind <= 4 {
            s.new_borrow = true
            s.value_parent = returned_parent
            s.value_slot = returned_root
        } else {
            s.value_slot = -1
        }
        if s.value_kind < 3 || s.value_kind > 4 { s.new_borrow = false }
        return s
    }
    if t == "true" || t == "false" {
        s.value = "0"
        if t == "true" { s.value = "1" }
        s.value_kind = 1
        return compiler_next(s)
    }
    if compiler_is_string_literal(t) {
        s.value = t
        s.value_kind = 17
        s.value_slot = -1
        return compiler_next(s)
    }
    if compiler_digit(__host_char_at(t, 0)) {
        int i = 0
        for i < len(t) {
            if !compiler_digit(__host_char_at(t, i)) { return compiler_fail(s, "invalid decimal integer") }
            i = i + 1
        }
        if len(t) > 18 { return compiler_fail(s, "integer literal exceeds supported 18 decimal digits") }
        i = 0
        for i + 1 < len(t) && __host_char_at(t, i) == "0" { i = i + 1 }
        s.value = "INT64_C(" + __host_slice(t, i, len(t)) + ")"
        s.value_kind = 1
        return compiler_next(s)
    }
    string unsupported = compiler_unsupported_token_message(t)
    if unsupported != "" { return compiler_subset_fail(s, unsupported) }
    int slot = compiler_find(s, t)
    s = compiler_available(s, slot)
    if s.error != "" { return s }
    s = compiler_next(s)
    if s.token == "[" {
        if s.kinds[slot] != 6 && s.kinds[slot] != 7 && s.kinds[slot] != 8 && s.kinds[slot] != 9 && s.kinds[slot] != 15 && s.kinds[slot] != 16 { return compiler_fail(s, "indexing requires an integer array or slice") }
        s = compiler_expression(compiler_next(s), 1)
        if s.value_kind != 1 { return compiler_fail(s, "array index requires an integer") }
        string index = s.value
        s = compiler_expect(s, "]")
        string data = compiler_var(slot)
        string length = compiler_array_length(s, slot)
        if s.kinds[slot] == 9 { data = compiler_var(slot) + "->data"; length = compiler_var(slot) + "->len" }
        if s.kinds[slot] == 15 || s.kinds[slot] == 16 { data = compiler_var(slot); length = compiler_var(slot) + "_len" }
        s.value = data + "[compiler_index(" + length + "," + index + ")]"
        s.value_kind = 1
        s.value_slot = -1
        return s
    }
    if s.token == "." {
        s = compiler_next(s)
        member_name := s.token
        method_look := compiler_next(s)
        int field = -1
        field = compiler_field_index(s, s.struct_ids[slot], member_name)
        if field < 0 {
            method_index := compiler_find_method(s, s.struct_ids[slot], member_name)
            if method_index >= 0 && method_look.token == "(" {
                if !compiler_is_struct_access_kind(s.kinds[slot]) { return compiler_fail(s, "method call requires an owned struct receiver") }
                if compiler_conflict(s, slot, false) { return compiler_fail(s, "cannot call method while receiver is mutably borrowed") }
                s = compiler_expect(method_look, "(")
                if s.token != ")" { return compiler_fail(s, "receiver methods in this subset do not accept extra arguments") }
                s = compiler_expect(s, ")")
                s.value = compiler_method_c_name(s, method_index) + "(" + compiler_var(slot) + ")"
                s.value_kind = s.method_returns[method_index]
                s.value_slot = -1
                s.value_struct_id = -1
                return s
            }
            return compiler_fail(s, "unknown owned struct field")
        }
        if !compiler_is_struct_access_kind(s.kinds[slot]) { return compiler_fail(s, "field access requires a pair") }
        field_state := compiler_field_live(s, slot, field)
        field_error := compiler_field_unavailable_message(field_state)
        if field_error != "" { return compiler_fail(s, field_error) }
        field_kind := compiler_struct_field_kind(s, s.struct_ids[slot], field)
        field_struct := compiler_struct_field_struct(s, s.struct_ids[slot], field)
        field_name := compiler_struct_field_name(s, s.struct_ids[slot], field)
        s.value = compiler_var(slot) + "->" + field_name
        s.value_kind = field_kind
        s.value_slot = slot
        s.value_field = field
        s.value_struct_id = field_struct
        s = compiler_next(s)
        if s.token == "." {
            if field_kind != 5 || field_struct < 0 { return compiler_fail(s, "nested field access requires a named struct field") }
            s = compiler_next(s)
            int nested_field = compiler_field_index(s, field_struct, s.token)
            if nested_field < 0 { return compiler_fail(s, "unknown nested owned struct field") }
            nested_state := compiler_nested_field_live(s, slot, field, nested_field)
            nested_error := compiler_field_unavailable_message(nested_state)
            if nested_error != "" { return compiler_fail(s, nested_error) }
            nested_kind := compiler_struct_field_kind(s, field_struct, nested_field)
            nested_struct := compiler_struct_field_struct(s, field_struct, nested_field)
            nested_name := compiler_struct_field_name(s, field_struct, nested_field)
            s.value = compiler_var(slot) + "->" + field_name + "->" + nested_name
            s.value_kind = nested_kind
            s.value_slot = slot
            s.value_parent_field = field
            s.value_field = nested_field
            s.value_struct_id = nested_struct
            s = compiler_next(s)
        }
        return s
    }
    s.value = compiler_var(slot)
    s.value_kind = s.kinds[slot]
    s.value_slot = slot
    s.value_struct_id = s.struct_ids[slot]
    return s
}

func compiler_expression(compiler_state initial, int minimum) compiler_state {
    s := initial
    s = compiler_atom(s)
    for s.error == "" && compiler_precedence(s.token) >= minimum {
        string op = s.token
        int precedence = compiler_precedence(op)
        string left = s.value
        string temporary = "s_left" + compiler_number(s.pos)
        if s.value_kind != 1 { return compiler_fail(s, "binary operator requires integers") }
        before := s
        if op != "&&" && op != "||" {
            s.code = s.code + "int64_t " + temporary + ";\n"
        }
        s = compiler_expression(compiler_next(s), precedence + 1)
        if s.value_kind != 1 { return compiler_fail(s, "binary operator requires integers") }
        string original_left = left
        if op != "&&" && op != "||" { left = temporary }
        string helper = ""
        if op == "+" { helper = "compiler_add" }
        if op == "-" { helper = "compiler_sub" }
        if op == "*" { helper = "compiler_mul" }
        if op == "/" { helper = "compiler_div" }
        if op == "%" { helper = "compiler_mod" }
        if helper != "" { s.value = helper + "(" + left + "," + s.value + ")" }
        else { s.value = "(" + left + op + s.value + ")" }
        if op != "&&" && op != "||" {
            s.value = "((" + temporary + " = " + original_left + ")," + s.value + ")"
        } else {
            int i = 0
            for i < before.count {
                if before.live[i] != s.live[i] { s.live[i] = 2 }
                i = i + 1
            }
        }
        s.value_kind = 1
        s.value_slot = -1
        s.new_borrow = false
    }
    return s
}

func compiler_bind(compiler_state initial, string name, bool declaration) compiler_state {
    s := initial
    int slot = compiler_find(s, name)
    bool is_declaration = declaration
    if is_declaration && slot >= 0 { is_declaration = false }
    if !is_declaration && slot < 0 { return compiler_fail(s, "assignment to unknown variable: " + name) }
    if !compiler_ident(name) { return compiler_fail(s, "expected variable name") }
    if is_declaration { slot = s.count }
    if !is_declaration && s.kinds[slot] != s.value_kind { return compiler_fail(s, "assignment changes variable type") }
    if !is_declaration && s.value_kind == 5 && s.struct_ids[slot] != s.value_struct_id { return compiler_fail(s, "assignment changes struct type") }
    if !is_declaration && compiler_is_borrow_kind(s.value_kind) { return compiler_fail(s, "reference reassignment is not supported") }
    string rhs = s.value
    int origin = s.value_slot
    if s.value_kind == 2 || s.value_kind == 5 || s.value_kind == 9 {
        if s.value_field >= 0 {
            if s.kinds[origin] != 5 { return compiler_fail(s, "field move requires a pair") }
            s = compiler_move_value_field_expr(s)
                    if s.error != "" { return s }
                    rhs = s.value
            origin = -1
        }
        if !is_declaration {
            if compiler_conflict(s, slot, true) { return compiler_fail(s, "cannot overwrite borrowed owner") }
        }
        if origin == slot { return compiler_fail(s, "self move is not supported") }
        if origin >= 0 {
            s = compiler_consume(s, origin)
            if s.value_kind == 5 {
                if s.value_struct_id >= 0 { rhs = "compiler_move_" + s.struct_names[s.value_struct_id] + "(&" + compiler_var(origin) + ")" }
                else { rhs = "compiler_pair_move(&" + compiler_var(origin) + ")" }
            }
            else if s.value_kind == 9 { rhs = "compiler_slice_move(&" + compiler_var(origin) + ")" }
            else { rhs = "compiler_move(&" + compiler_var(origin) + ")" }
        }
    }
    int parent = s.value_parent
    if compiler_is_borrow_kind(s.value_kind) && !s.new_borrow {
        if compiler_is_mutable_borrow_kind(s.value_kind) { return compiler_fail(s, "mutable reference copying is not supported; create a reborrow") }
        parent = s.parents[origin]
        origin = s.roots[origin]
    }
    string ctype = compiler_c_type_for_kind(s, s.value_kind, s.value_struct_id)
    if s.value_kind == 6 { ctype = "int64_t " }
    if !is_declaration { ctype = "" }
    if !is_declaration && (s.value_kind == 2 || s.value_kind == 5 || s.value_kind == 9) {
        string replacement_type = "int64_t *"
        if s.value_kind == 5 { replacement_type = compiler_c_type_for_kind(s, s.value_kind, s.value_struct_id) }
        if s.value_kind == 9 { replacement_type = "compiler_slice *" }
        s.code = s.code + "{ " + replacement_type + "compiler_new = " + rhs + ";\n" + compiler_overwrite_old_owner(s, slot) + compiler_var(slot) + " = compiler_new; }\n"
    } else if s.value_kind == 6 {
        if !is_declaration { return compiler_fail(s, "array reassignment is not supported") }
        s.code = s.code + ctype + compiler_var(slot) + "[" + compiler_number(s.value_array_length) + "] = " + rhs + ";\n"
    } else {
        s.code = s.code + ctype + compiler_var(slot) + " = " + rhs + ";\n"
    }
    s.code = s.code + "(void)" + compiler_var(slot) + ";\n"
    s.names[slot] = name
    s.kinds[slot] = s.value_kind
    s.struct_ids[slot] = s.value_struct_id
    s.live[slot] = 1
    s.roots[slot] = -1
    s.parents[slot] = -1
    s.loan_fields[slot] = -1
    s.loan_parent_fields[slot] = -1
    s.array_lengths[slot] = 0
    if s.value_kind == 5 {
        struct_id := s.value_struct_id
        field_count := 2
        if struct_id >= 0 { field_count = s.struct_field_counts[struct_id] }
        fi := 0
        for fi < field_count {
            s.field_state[slot * 8 + fi] = 1
            s = compiler_clear_nested_field_state(s, slot, fi)
            fi = fi + 1
        }
    }
    if s.value_kind == 6 { s.array_lengths[slot] = s.value_array_length }
    if compiler_is_borrow_kind(s.value_kind) {
        s.roots[slot] = origin
        s.parents[slot] = parent
        if s.value_field >= 0 { s.loan_fields[slot] = s.value_field }
        if s.value_parent_field >= 0 { s.loan_parent_fields[slot] = s.value_parent_field }
        if s.value_parent_field >= 0 { s = compiler_add_nested_field_borrow(s, origin, s.value_parent_field, s.value_field) }
        else if s.value_field >= 0 { s = compiler_add_field_borrow(s, origin, s.value_field) }
    }
    if declaration { s.count = s.count + 1 }
    return s
}

func compiler_declare_int_locals(compiler_state initial) compiler_state {
    s := compiler_next(initial)
    int decl_line = initial.line
    while s.error == "" && s.token != "" {
        string name = s.token
        if !compiler_ident(name) { return compiler_fail(s, "expected int local name") }
        if compiler_find(s, name) >= 0 { return compiler_fail(s, "duplicate or shadowed variable: " + name) }
        int slot = s.count
        string initial_value = "0"
        s = compiler_next(s)
        if s.token == "=" {
            s = compiler_expression(compiler_next(s), 1)
            if s.value_kind != 1 { return compiler_fail(s, "int local initializer must be an int") }
            initial_value = s.value
        }
        s.code = s.code + "int64_t " + compiler_var(slot) + " = " + initial_value + ";\n(void)" + compiler_var(slot) + ";\n"
        s.names[slot] = name
        s.kinds[slot] = 1
        s.struct_ids[slot] = -1
        s.live[slot] = 1
        s.roots[slot] = -1
        s.parents[slot] = -1
        s.loan_fields[slot] = -1
        s.loan_parent_fields[slot] = -1
        s.array_lengths[slot] = 0
        s.count = s.count + 1
        if s.token == ";" { return compiler_next(s) }
        if s.line != decl_line { return s }
        if s.token != "," { return compiler_fail(s, "expected ',' after int local name") }
        s = compiler_next(s)
        if s.line != decl_line { return compiler_fail(s, "expected int local name after ','") }
    }
    return s
}

func compiler_block(compiler_state initial) compiler_state {
    s := initial
    int floor = s.count
    s.depth = s.depth + 1
    if s.depth > 64 { return compiler_fail(s, "block nesting limit exceeded") }
    s = compiler_expect(s, "{")
    s.code = s.code + "{\n"
    for s.error == "" && s.token != "}" && s.token != "" {
        if s.terminated != 0 { return compiler_fail(s, "unreachable statement") }
        s = compiler_statement(s)
    }
    s = compiler_expect(s, "}")
    if s.terminated == 0 { s.code = s.code + compiler_cleanup(s, floor) }
    s.code = s.code + "}\n"
    s.count = floor
    s.depth = s.depth - 1
    return s
}

func compiler_statement(compiler_state initial) compiler_state {
    s := initial
    string unsupported = compiler_unsupported_token_message(s.token)
    if unsupported != "" { return compiler_subset_fail(s, unsupported) }
    if s.token == "{" { return compiler_block(s) }
    if s.token == "if" {
        s = compiler_expression(compiler_next(s), 1)
        if s.value_kind != 1 { return compiler_fail(s, "condition requires an integer") }
        s.code = s.code + "if (" + s.value + ")\n"
        before := s
        yes := compiler_block(s)
        if yes.error != "" { return yes }
        no := before
        no.pos = yes.pos; no.line = yes.line; no.token = yes.token; no.code = yes.code
        if no.token == "else" {
            no = compiler_next(no)
            no.code = no.code + "else\n"
            no = compiler_block(no)
        }
        if no.error != "" { return no }
        int i = 0
        for i < before.count {
            if yes.terminated == 0 && no.terminated != 0 { no.live[i] = yes.live[i] }
            else if yes.terminated == 0 && no.terminated == 0 && yes.live[i] != no.live[i] { no.live[i] = 2 }
            i = i + 1
        }
        no = compiler_merge_field_states(before, yes, no, before.count)
        no = compiler_merge_nested_field_states(before, yes, no, before.count)
        no = compiler_merge_field_borrow_states(before, yes, no, before.count)
        no = compiler_merge_nested_field_borrow_states(before, yes, no, before.count)
        int both_terminated = 0
        if yes.terminated != 0 && no.terminated != 0 { both_terminated = 1 }
        if s.return_kind >= 3 && s.return_kind <= 4 {
            int returned_param = -1
            if yes.terminated != 0 { returned_param = yes.return_param }
            if no.terminated != 0 {
                if returned_param >= 0 && no.return_param != returned_param { return compiler_fail(no, "reference return parameter differs across paths") }
                returned_param = no.return_param
            }
            if returned_param >= 0 {
                no.return_param = returned_param
                no.function_return_params[no.function_count - 1] = returned_param
            }
        }
        no.terminated = both_terminated
        return no
    }
    if s.token == "while" {
        int old_floor = s.loop_floor
        s.loop_floor = s.count
        s = compiler_expression(compiler_next(s), 1)
        if s.value_kind != 1 { return compiler_fail(s, "condition requires an integer") }
        s.code = s.code + "while (" + s.value + ")\n"
        int old_cleanup = s.loop_cleanup
        s.loop_cleanup = s.count
        s.loop_floor = s.count
        body := compiler_block(s)
        body.loop_floor = old_floor
        body.loop_cleanup = old_cleanup
        body.terminated = 0
        return body
    }
    if s.token == "for" {
        s = compiler_next(s)
        bool has_for_parens = false
        if s.token == "(" {
            has_for_parens = true
            s = compiler_next(s)
        }
        s = compiler_statement(s)
        if s.error != "" { return s }
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "for condition requires an integer") }
        string condition = s.value
        s = compiler_expect(s, ";")
        string step_name = s.token
        s = compiler_next(s)
        int step_slot = compiler_find(s, step_name)
        s = compiler_available(s, step_slot)
        if s.error != "" { return s }
        if s.kinds[step_slot] != 1 { return compiler_fail(s, "for step currently requires an integer variable") }
        string step_code = ""
        if s.token == "=" {
            s = compiler_expression(compiler_next(s), 1)
            if s.value_kind != 1 { return compiler_fail(s, "for step requires an integer expression") }
            step_code = compiler_var(step_slot) + " = " + s.value + ";\n"
        } else if s.token == "+" {
            s = compiler_next(s)
            if s.token == "+" {
                step_code = compiler_var(step_slot) + " = compiler_add(" + compiler_var(step_slot) + ",1);\n"
                s = compiler_next(s)
            } else if s.token == "=" {
                s = compiler_expression(compiler_next(s), 1)
                if s.value_kind != 1 { return compiler_fail(s, "for step += requires an integer expression") }
                step_code = compiler_var(step_slot) + " = compiler_add(" + compiler_var(step_slot) + "," + s.value + ");\n"
            } else { return compiler_fail(s, "for step expects assignment") }
        } else { return compiler_fail(s, "for step expects assignment") }
        if has_for_parens { s = compiler_expect(s, ")") }
        int old_floor = s.loop_floor
        int old_cleanup = s.loop_cleanup
        int floor = s.count
        s.loop_floor = s.count
        s.loop_cleanup = s.count
        s.depth = s.depth + 1
        if s.depth > 64 { return compiler_fail(s, "block nesting limit exceeded") }
        s = compiler_expect(s, "{")
        s.code = s.code + "while (" + condition + ")\n{\n"
        for s.error == "" && s.token != "}" && s.token != "" {
            if s.terminated != 0 { return compiler_fail(s, "unreachable statement") }
            s = compiler_statement(s)
        }
        s = compiler_expect(s, "}")
        if s.terminated == 0 { s.code = s.code + step_code + compiler_cleanup(s, floor) }
        s.code = s.code + "}\n"
        s.count = floor
        s.depth = s.depth - 1
        s.loop_floor = old_floor
        s.loop_cleanup = old_cleanup
        s.terminated = 0
        return s
    }
    if s.token == "return" {
        if s.return_kind == 0 {
            s = compiler_next(s)
            s = compiler_optional_semicolon(s)
            string finish = "return;\n"
            if s.function_main { finish = "return compiler_finish(0);\n" }
            s.code = s.code + compiler_cleanup(s, 0) + finish
            s.terminated = 1
            return s
        }
        s = compiler_expression(compiler_next(s), 1)
        if s.value_kind != s.return_kind { return compiler_fail(s, "return type mismatch") }
        if s.return_kind == 5 && s.value_struct_id != s.function_return_structs[s.function_count - 1] { return compiler_fail(s, "return struct type mismatch") }
        if s.return_kind >= 3 && s.return_kind <= 4 && (s.value_slot < 0 || s.value_slot >= s.parameter_count) {
            return compiler_fail(s, "reference return must use a parameter")
        }
        if s.return_kind >= 3 && s.return_kind <= 4 {
            if s.return_param < 0 { s.return_param = s.value_slot }
            else if s.return_param != s.value_slot { return compiler_fail(s, "reference return parameter differs across paths") }
            s.function_return_params[s.function_count - 1] = s.return_param
        }
        string result_type = "int64_t "
        if s.value_kind == 2 {
            result_type = "int64_t *"
            if s.value_field >= 0 {
                s = compiler_move_value_field_expr(s)
                if s.error != "" { return s }
            } else if s.value_slot >= 0 {
                int origin = s.value_slot
                s = compiler_consume(s, origin)
                s.value = "compiler_move(&" + compiler_var(origin) + ")"
            }
        } else if s.value_kind == 3 { result_type = "const int64_t *" }
        else if s.value_kind == 4 { result_type = "int64_t *" }
        else if s.value_kind == 5 {
            result_type = compiler_c_type_for_kind(s, s.value_kind, s.value_struct_id)
            if s.value_field >= 0 {
                s = compiler_move_value_field_expr(s)
                if s.error != "" { return s }
            } else if s.value_slot >= 0 {
                int origin = s.value_slot
                s = compiler_consume(s, origin)
                if s.value_struct_id >= 0 { s.value = "compiler_move_" + s.struct_names[s.value_struct_id] + "(&" + compiler_var(origin) + ")" }
                else { s.value = "compiler_pair_move(&" + compiler_var(origin) + ")" }
            }
        }
        else if s.value_kind == 9 {
            result_type = "compiler_slice *"
            if s.value_field >= 0 {
                s = compiler_move_value_field_expr(s)
                if s.error != "" { return s }
            } else if s.value_slot >= 0 {
                int origin = s.value_slot
                s = compiler_consume(s, origin)
                s.value = "compiler_slice_move(&" + compiler_var(origin) + ")"
            }
        }
        s = compiler_optional_semicolon(s)
        string finish = "return compiler_result;"
        if s.function_main { finish = "return compiler_finish(compiler_result);" }
        s.code = s.code + "{ " + result_type + "compiler_result = " + s.value + ";\n" + compiler_cleanup(s, 0) + finish + " }\n"
        s.terminated = 1
        return s
    }
    if s.token == "println" || s.token == "print" {
        bool newline = s.token == "println"
        s = compiler_expect(compiler_next(s), "(")
        s = compiler_expression(s, 1)
        if s.value_kind != 17 { return compiler_fail(s, "print/println currently expects a string") }
        string message = s.value
        if s.token == "," {
            s = compiler_expression(compiler_next(s), 1)
            if s.value_kind != 1 { return compiler_fail(s, "print/println integer argument must be an int") }
            s.code = s.code + "fputs(" + message + ", stdout);\nfputc(' ', stdout);\nfprintf(stdout, \"%lld\", (long long)(" + s.value + "));\n"
        } else {
            s.code = s.code + "fputs(" + message + ", stdout);\n"
        }
        if newline { s.code = s.code + "fputc('\\n', stdout);\n" }
        s = compiler_expect(s, ")")
        s = compiler_optional_semicolon(s)
        return s
    }
    if s.token == "break" || s.token == "continue" {
        string op = s.token
        if s.loop_floor < 0 { return compiler_fail(s, "loop control outside a loop") }
        s = compiler_optional_semicolon(compiler_next(s))
        s.code = s.code + compiler_cleanup(s, s.loop_cleanup) + op + ";\n"
        s.terminated = 1
        return s
    }
    if s.token == "drop" {
        s = compiler_expect(compiler_next(s), "(")
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] == 2 || s.kinds[slot] == 5 {
            s = compiler_consume(s, slot)
            s.code = s.code + compiler_drop_owner(s, slot)
        } else if s.kinds[slot] == 9 {
            s = compiler_consume(s, slot)
            s.code = s.code + "compiler_slice_drop(&" + compiler_var(slot) + ");\n"
        } else if s.kinds[slot] >= 3 {
            if compiler_child_conflict(s, slot, true) { return compiler_fail(s, "cannot drop reference with a live reborrow") }
            if s.loop_floor >= 0 && slot < s.loop_floor { return compiler_fail(s, "cannot end an outer borrow inside a loop") }
            if s.loan_parent_fields[slot] >= 0 { s = compiler_drop_nested_field_borrow(s, s.roots[slot], s.loan_parent_fields[slot], s.loan_fields[slot]) }
            else if s.loan_fields[slot] >= 0 { s = compiler_drop_field_borrow(s, s.roots[slot], s.loan_fields[slot]) }
            s.live[slot] = 0
        } else { return compiler_fail(s, "drop requires an owner or reference") }
        s = compiler_expect(compiler_next(s), ")")
        return compiler_optional_semicolon(s)
    }
    if s.token == "assert" {
        s = compiler_expect(compiler_next(s), "(")
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "assert requires an integer") }
        s = compiler_expect(s, ")")
        s = compiler_optional_semicolon(s)
        s.code = s.code + "compiler_assert(" + s.value + ");\n"
        return s
    }
    if s.token == "*" {
        s = compiler_next(s)
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        string target = compiler_var(slot)
        if s.kinds[slot] == 5 {
            s = compiler_next(s)
            if s.token != "." { return compiler_fail(s, "pair write requires a field") }
            s = compiler_next(s)
            int field = -1
            field = compiler_field_index(s, s.struct_ids[slot], s.token)
            if field < 0 { return compiler_fail(s, "unknown owned struct field") }
            if compiler_struct_field_kind(s, s.struct_ids[slot], field) != 2 { return compiler_fail(s, "pair write requires an owned box field") }
            field_state := compiler_field_live(s, slot, field)
            field_error := compiler_field_unavailable_message(field_state)
            if field_error != "" { return compiler_fail(s, field_error) }
            if compiler_conflict_at(s, slot, field, true) { return compiler_fail(s, "cannot write pair field during a borrow") }
            target = compiler_var(slot) + "->" + compiler_struct_field_name(s, s.struct_ids[slot], field)
            s = compiler_next(s)
        } else {
            if s.kinds[slot] != 2 && s.kinds[slot] != 4 { return compiler_fail(s, "write requires an owner or mutable reference") }
            if s.kinds[slot] == 4 && compiler_child_conflict(s, slot, true) { return compiler_fail(s, "cannot write reference with a live reborrow") }
            if s.kinds[slot] == 2 && compiler_conflict(s, slot, true) { return compiler_fail(s, "cannot write borrowed owner") }
            s = compiler_next(s)
        }
        s = compiler_expect(s, "=")
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "box write requires an integer") }
        s = compiler_available(s, slot)
        s = compiler_optional_semicolon(s)
        s.code = s.code + "*" + target + " = " + s.value + ";\n"
        return s
    }
    if s.token == "int" {
        return compiler_declare_int_locals(s)
    }
    string name = s.token
    if name == "var" || name == "let" || name == "const" {
        return compiler_subset_fail(s, "typed declarations; use `name := value` in this subset")
    }
    s = compiler_next(s)
    if s.token == "(" && compiler_find_func(s, name) >= 0 {
        int function_index = compiler_find_func(s, name)
        if s.function_returns[function_index] != 0 { return compiler_fail(s, "non-void function result must be used") }
        s = compiler_expect(s, "(")
        string args = ""
        string evaluations = ""
        string call_id = compiler_number(s.pos)
        int arg = 0
        for s.error == "" && s.token != ")" && s.token != "" {
            if arg > 0 { s = compiler_expect(s, ",") }
            s = compiler_expression(s, 1)
            if arg >= s.function_counts[function_index] { return compiler_fail(s, "too many function arguments") }
            int expected = s.function_param_kinds[s.function_starts[function_index] + arg]
            if s.value_kind != expected { return compiler_fail(s, "function argument type mismatch") }
            if expected == 5 && s.value_struct_id != s.function_param_structs[s.function_starts[function_index] + arg] { return compiler_fail(s, "function argument struct type mismatch") }
            string temporary = "s_arg" + call_id + "_" + compiler_number(arg)
            string argument_type = "int64_t "
            if expected == 17 { argument_type = "const char *" }
            s.code = s.code + argument_type + temporary + ";\n"
            evaluations = evaluations + temporary + " = " + s.value + ";\n"
            if arg > 0 { args = args + "," }
            args = args + temporary
            arg = arg + 1
        }
        if arg != s.function_counts[function_index] { return compiler_fail(s, "wrong number of function arguments") }
        s = compiler_expect(s, ")")
        s = compiler_optional_semicolon(s)
        s.code = s.code + evaluations + s.function_names[function_index] + "(" + args + ");\n"
        return s
    }
    if s.token == "[" {
        int slot = compiler_find(s, name)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] != 6 && s.kinds[slot] != 7 && s.kinds[slot] != 8 && s.kinds[slot] != 9 && s.kinds[slot] != 15 && s.kinds[slot] != 16 { return compiler_fail(s, "index assignment requires an integer array or slice") }
        s = compiler_expression(compiler_next(s), 1)
        if s.value_kind != 1 { return compiler_fail(s, "array index requires an integer") }
        string index = s.value
        s = compiler_expect(s, "]")
        s = compiler_expect(s, "=")
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "array elements require integers") }
        string data = compiler_var(slot)
        string length = compiler_array_length(s, slot)
        if s.kinds[slot] == 9 { data = compiler_var(slot) + "->data"; length = compiler_var(slot) + "->len" }
        if s.kinds[slot] == 15 || s.kinds[slot] == 16 { data = compiler_var(slot); length = compiler_var(slot) + "_len" }
        s.code = s.code + data + "[compiler_index(" + length + "," + index + ")] = " + s.value + ";\n"
        s = compiler_optional_semicolon(s)
        return s
    }
    if s.token == "." {
        int slot = compiler_find(s, name)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] != 5 { return compiler_fail(s, "field assignment requires an owned struct") }
        s = compiler_next(s)
        int field = compiler_field_index(s, s.struct_ids[slot], s.token)
        if field < 0 { return compiler_fail(s, "unknown owned struct field") }
        int field_kind = compiler_struct_field_kind(s, s.struct_ids[slot], field)
        int field_struct = compiler_struct_field_struct(s, s.struct_ids[slot], field)
        if field_kind != 2 && field_kind != 5 && field_kind != 9 { return compiler_fail(s, "field assignment requires an owned field") }
        if compiler_conflict_at(s, slot, field, true) { return compiler_fail(s, "cannot overwrite borrowed struct field") }
        s = compiler_expect(compiler_next(s), "=")
        s = compiler_expression(s, 1)
        if s.value_kind != field_kind { return compiler_fail(s, "field assignment type mismatch") }
        if field_kind == 5 && s.value_struct_id != field_struct { return compiler_fail(s, "field assignment struct type mismatch") }
        string rhs = s.value
        int origin = s.value_slot
        if s.value_field >= 0 {
            s = compiler_move_value_field_expr(s)
                    if s.error != "" { return s }
                    rhs = s.value
        } else if origin >= 0 {
            if origin == slot { return compiler_fail(s, "self field assignment is not supported") }
            s = compiler_consume(s, origin)
            if s.error != "" { return s }
            if field_kind == 2 { rhs = "compiler_move(&" + compiler_var(origin) + ")" }
            else if field_kind == 5 {
                if s.value_struct_id >= 0 { rhs = "compiler_move_" + s.struct_names[s.value_struct_id] + "(&" + compiler_var(origin) + ")" }
                else { rhs = "compiler_pair_move(&" + compiler_var(origin) + ")" }
            }
            else if field_kind == 9 { rhs = "compiler_slice_move(&" + compiler_var(origin) + ")" }
        }
        string target = compiler_var(slot) + "->" + compiler_struct_field_name(s, s.struct_ids[slot], field)
        string replacement_type = compiler_c_type_for_kind(s, field_kind, field_struct)
        s.code = s.code + "{ " + replacement_type + "compiler_new = " + rhs + ";\n" + compiler_drop_field_owner_code(s, slot, field, field_kind, field_struct) + target + " = compiler_new; }\n"
        s.field_state[slot * 8 + field] = 1
        s = compiler_optional_semicolon(s)
        return s
    }
    if s.token == "+" {
        int slot = compiler_find(s, name)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] != 1 { return compiler_fail(s, "integer update requires an integer variable") }
        s = compiler_next(s)
        if s.token == "+" {
            s.code = s.code + compiler_var(slot) + " = compiler_add(" + compiler_var(slot) + ",1);\n"
            s = compiler_next(s)
            return compiler_optional_semicolon(s)
        }
        if s.token == "=" {
            s = compiler_expression(compiler_next(s), 1)
            if s.value_kind != 1 { return compiler_fail(s, "+= requires an integer expression") }
            s.code = s.code + compiler_var(slot) + " = compiler_add(" + compiler_var(slot) + "," + s.value + ");\n"
            return compiler_optional_semicolon(s)
        }
        return compiler_fail(s, "expected ++ or += after integer variable")
    }
    bool declaration = s.token == ":="
    if !declaration && s.token != "=" { return compiler_fail(s, "expected := or =; unsupported statement") }
    s = compiler_expression(compiler_next(s), 1)
    s = compiler_bind(s, name, declaration)
    return compiler_optional_semicolon(s)
}

func compiler_parse_helper(compiler_state initial) compiler_state {
    s := initial
    s = compiler_expect(s, "func")
    string name = s.token
    if !compiler_ident(name) || name == "main" { return compiler_fail(s, "expected helper function name") }
    s = compiler_next(s)
    if s.token == "[" {
        return compiler_parse_generic_identity_helper(s, name)
    }
    s = compiler_expect(s, "(")
    int param_count = 0
    s.count = 0
    for s.token != ")" && s.token != "" {
        if param_count > 0 { s = compiler_expect(s, ",") }
        int kind = 0
        int param_struct = -1
        if s.token == "int" { kind = 1 }
        else if s.token == "mutint" { kind = 8 }
        else if s.token == "box" { kind = 2 }
        else if s.token == "ref" { kind = 3 }
        else if s.token == "mutref" { kind = 4 }
        else if s.token == "pair" { kind = 5 }
        else if s.token == "slice" { kind = 9 }
        else if s.token == "mutslice" { kind = 16 }
        else if s.token == "string" { kind = 17 }
        else if compiler_is_struct_type(s.token) {
            kind = 5
            param_struct = compiler_find_struct(s, s.token)
            if param_struct < 0 { return compiler_fail(s, "unknown struct: " + s.token) }
        }
        else { return compiler_fail(s, "function parameters require int, string, box, ref, mutref or pair") }
        s = compiler_next(s)
        if kind == 1 && s.token == "[" {
            s = compiler_expect(s, "[")
            s = compiler_expect(s, "]")
            kind = 7
        }
        if kind == 8 && s.token == "[" {
            s = compiler_expect(s, "[")
            s = compiler_expect(s, "]")
        }
        if kind == 9 && s.token == "[" {
            s = compiler_expect(s, "[")
            s = compiler_expect(s, "]")
            kind = 15
        }
        if kind == 16 && s.token == "[" {
            s = compiler_expect(s, "[")
            s = compiler_expect(s, "]")
        }
        string param = s.token
        if !compiler_ident(param) { return compiler_fail(s, "expected parameter name") }
        if param_count >= 16 { return compiler_fail(s, "too many function parameters") }
        s.names[param_count] = param
        s.kinds[param_count] = kind
        s.struct_ids[param_count] = param_struct
        param_count = param_count + 1
        s = compiler_next(s)
    }
    s = compiler_expect(s, ")")
    s.return_kind = 0
    int return_struct = -1
    if s.token == "int" { s.return_kind = 1; s = compiler_next(s) }
    else if s.token == "box" { s.return_kind = 2; s = compiler_next(s) }
    else if s.token == "ref" { s.return_kind = 3 }
    else if s.token == "mutref" { s.return_kind = 4 }
    else if s.token == "pair" { s.return_kind = 5 }
    else if compiler_is_struct_type(s.token) {
        s.return_kind = 5
        return_struct = compiler_find_struct(s, s.token)
        if return_struct < 0 { return compiler_fail(s, "unknown struct: " + s.token) }
    }
    else if s.token == "slice" { s.return_kind = 9 }
    else if s.token != "{" { return compiler_fail(s, "function return type must be int, box, ref, mutref, pair or struct") }
    if s.return_kind == 3 || s.return_kind == 4 || s.return_kind == 5 || s.return_kind == 9 { s = compiler_next(s) }
    s.parameter_count = param_count
    s.return_param = -1

    int start = s.function_param_total
    s.function_names[s.function_count] = name
    s.function_counts[s.function_count] = param_count
    s.function_returns[s.function_count] = s.return_kind
    s.function_return_structs[s.function_count] = return_struct
    s.function_return_params[s.function_count] = s.return_param
    s.function_starts[s.function_count] = start
    int pi = 0
    for pi < param_count {
        s.function_param_kinds[s.function_param_total + pi] = s.kinds[pi]
        s.function_param_structs[s.function_param_total + pi] = s.struct_ids[pi]
        pi = pi + 1
    }
    s.function_param_total = s.function_param_total + param_count
    s.function_count = s.function_count + 1

    string signature = "static int64_t " + name + "("
    if s.return_kind == 0 { signature = "static void " + name + "(" }
    if s.return_kind == 2 || s.return_kind == 4 { signature = "static int64_t *" + name + "(" }
    else if s.return_kind == 5 { signature = "static " + compiler_c_type_for_kind(s, s.return_kind, return_struct) + name + "(" }
    else if s.return_kind == 9 { signature = "static compiler_slice *" + name + "(" }
    else if s.return_kind == 3 { signature = "static const int64_t *" + name + "(" }
    pi = 0
    for pi < param_count {
        if pi > 0 { signature = signature + ", " }
        signature = signature + compiler_c_type_for_kind(s, s.kinds[pi], s.function_param_structs[start + pi])
        signature = signature + "p" + compiler_number(pi)
        if s.kinds[pi] == 7 || s.kinds[pi] == 8 || s.kinds[pi] == 15 || s.kinds[pi] == 16 { signature = signature + ", int64_t p" + compiler_number(pi) + "_len" }
        pi = pi + 1
    }
    signature = signature + ")\n"

    s.count = 0
    s.depth = 0
    s.loop_floor = -1
    s.loop_cleanup = -1
    s.terminated = 0
    s.function_name = name
    s.function_main = false
    s.code = s.code + signature + "{\n"
    pi = 0
    for pi < param_count {
        string ctype = compiler_c_type_for_kind(s, s.kinds[pi], s.function_param_structs[start + pi])
        s.code = s.code + ctype + compiler_var(pi) + " = p" + compiler_number(pi) + ";\n"
        if s.kinds[pi] == 7 || s.kinds[pi] == 8 || s.kinds[pi] == 15 || s.kinds[pi] == 16 { s.code = s.code + "int64_t " + compiler_var(pi) + "_len = p" + compiler_number(pi) + "_len;\n" }
        s.code = s.code + "(void)" + compiler_var(pi) + ";\n"
        s.live[pi] = 1
        s.struct_ids[pi] = s.function_param_structs[start + pi]
        s.roots[pi] = -1
        if s.kinds[pi] >= 3 && s.kinds[pi] <= 4 { s.roots[pi] = pi }
        s.parents[pi] = -1
        s.loan_fields[pi] = -1
        s.loan_parent_fields[pi] = -1
        s.array_lengths[pi] = 0
        if s.kinds[pi] == 7 || s.kinds[pi] == 8 || s.kinds[pi] == 15 || s.kinds[pi] == 16 { s.array_lengths[pi] = -1 }
        if s.kinds[pi] == 5 {
            struct_id := s.function_param_structs[start + pi]
            field_count := 2
            if struct_id >= 0 { field_count = s.struct_field_counts[struct_id] }
            fi := 0
            for fi < field_count {
                s.field_state[pi * 8 + fi] = 1
                s = compiler_clear_nested_field_state(s, pi, fi)
                fi = fi + 1
            }
        }
        s.count = s.count + 1
        pi = pi + 1
    }
    s = compiler_block(s)
    if s.error != "" { return s }
    if s.return_kind != 0 && s.return_kind != 1 && s.terminated == 0 { return compiler_fail(s, "non-integer function must return on every path") }
    if s.terminated == 0 {
        if s.return_kind == 0 { s.code = s.code + compiler_cleanup(s, 0) + "return;\n" }
        else { s.code = s.code + compiler_cleanup(s, 0) + "return 0;\n" }
    }
    s.code = s.code + "}\n"
    return s
}

func compiler_register_generated_function(compiler_state initial, string name, int param_kind, int return_kind) compiler_state {
    s := initial
    if s.function_count >= len(s.function_names) { return compiler_fail(s, "too many functions") }
    start := s.function_param_total
    s.function_names[s.function_count] = name
    s.function_counts[s.function_count] = 1
    s.function_returns[s.function_count] = return_kind
    s.function_return_structs[s.function_count] = -1
    s.function_return_params[s.function_count] = -1
    s.function_starts[s.function_count] = start
    s.function_param_kinds[start] = param_kind
    s.function_param_structs[start] = -1
    s.function_param_total = s.function_param_total + 1
    s.function_count = s.function_count + 1
    s
}

func compiler_parse_generic_identity_helper(compiler_state initial, string name) compiler_state {
    s := initial
    s = compiler_expect(s, "[")
    type_param := s.token
    if !compiler_ident(type_param) { return compiler_fail(s, "expected generic type parameter") }
    s = compiler_expect(compiler_next(s), "]")
    s = compiler_expect(s, "(")
    if s.token != type_param { return compiler_fail(s, "generic function P0 requires parameter type T") }
    s = compiler_next(s)
    param_name := s.token
    if !compiler_ident(param_name) { return compiler_fail(s, "expected generic parameter name") }
    s = compiler_expect(compiler_next(s), ")")
    if s.token != type_param { return compiler_fail(s, "generic function P0 requires return type T") }
    s = compiler_expect(compiler_next(s), "{")
    s = compiler_expect(s, "return")
    if s.token != param_name { return compiler_fail(s, "generic function P0 body must return its parameter") }
    s = compiler_next(s)
    s = compiler_optional_semicolon(s)
    s = compiler_expect(s, "}")
    int_name := compiler_generic_instance_name(name, 1)
    box_name := compiler_generic_instance_name(name, 2)
    s = compiler_register_generated_function(s, int_name, 1, 1)
    if s.error != "" { return s }
    s = compiler_register_generated_function(s, box_name, 2, 2)
    if s.error != "" { return s }
    s.code = s.code + "static int64_t " + int_name + "(int64_t p0)\n{\nint64_t s_v0 = p0;\n(void)s_v0;\nreturn s_v0;\n}\n"
    s.code = s.code + "static int64_t *" + box_name + "(int64_t *p0)\n{\nint64_t *s_v0 = p0;\n(void)s_v0;\nint64_t *compiler_result = compiler_move(&s_v0);\nreturn compiler_result;\n}\n"
    return s
}

func compiler_parse_receiver_method(compiler_state initial) compiler_state {
    s := initial
    s = compiler_expect(s, "func")
    s = compiler_expect(s, "(")
    if !compiler_is_struct_type(s.token) { return compiler_fail(s, "receiver type must be an owned struct") }
    type_name := s.token
    struct_id := compiler_find_struct(s, type_name)
    if struct_id < 0 { return compiler_fail(s, "receiver type is not declared: " + type_name) }
    s = compiler_next(s)
    s = compiler_expect(s, "*")
    receiver := s.token
    if !compiler_ident(receiver) { return compiler_fail(s, "expected receiver name") }
    s = compiler_next(s)
    s = compiler_expect(s, ")")
    method_name := s.token
    if !compiler_ident(method_name) { return compiler_fail(s, "expected receiver method name") }
    if method_name != "drop" && compiler_find_method(s, struct_id, method_name) >= 0 { return compiler_fail(s, "duplicate receiver method for type: " + type_name + "." + method_name) }
    if method_name != "drop" && s.method_count >= len(s.method_names) { return compiler_fail(s, "too many receiver methods") }
    s = compiler_next(s)
    s = compiler_expect(s, "(")
    if s.token != ")" {
        if method_name == "drop" { return compiler_fail(s, "drop method must not have parameters") }
        return compiler_fail(s, "receiver methods in this subset do not accept extra parameters")
    }
    s = compiler_expect(s, ")")
    if method_name == "drop" {
        if s.token != "{" { return compiler_fail(s, "drop method must not return a value") }
        if s.struct_custom_drops[struct_id] != 0 { return compiler_fail(s, "duplicate drop method for type: " + type_name) }
        return compiler_parse_drop_body(s, type_name, struct_id, receiver)
    }
    method_return := 0
    if s.token == "int" {
        method_return = 1
        s = compiler_next(s)
    } else if s.token != "{" {
        return compiler_fail(s, "receiver method return type must be int or omitted")
    }
    method_index := s.method_count
    s.method_names[method_index] = method_name
    s.method_structs[method_index] = struct_id
    s.method_returns[method_index] = method_return
    s.method_count = s.method_count + 1
    result_type := "void "
    if method_return == 1 { result_type = "int64_t " }
    s.return_kind = method_return
    s.parameter_count = 1
    s.return_param = -1
    s.count = 0
    s.depth = 0
    s.loop_floor = -1
    s.loop_cleanup = -1
    s.terminated = 0
    s.function_name = compiler_method_c_name(s, method_index)
    s.function_main = false
    s.code = s.code + "static " + result_type + compiler_method_c_name(s, method_index) + "(S_" + type_name + " *p0)\n{\n"
    s.code = s.code + "S_" + type_name + " *" + compiler_var(0) + " = p0;\n(void)" + compiler_var(0) + ";\n"
    s.names[0] = receiver
    s.kinds[0] = 20
    s.live[0] = 1
    s.struct_ids[0] = struct_id
    s.roots[0] = -1
    s.parents[0] = -1
    s.loan_fields[0] = -1
    s.loan_parent_fields[0] = -1
    field_count := s.struct_field_counts[struct_id]
    fi := 0
    for fi < field_count {
        s.field_state[fi] = 1
        s = compiler_clear_nested_field_state(s, 0, fi)
        fi = fi + 1
    }
    s.count = 1
    s = compiler_block(s)
    if s.error != "" { return s }
    if s.terminated == 0 {
        if method_return == 0 { s.code = s.code + "return;\n" }
        else { s.code = s.code + "return 0;\n" }
    }
    s.code = s.code + "}\n"
    return s
}

func compiler_parse_drop_method(compiler_state initial) compiler_state {
    s := initial
    s = compiler_expect(s, "func")
    s = compiler_expect(s, "(")
    if !compiler_is_struct_type(s.token) { return compiler_fail(s, "drop receiver type must be an owned struct") }
    type_name := s.token
    struct_id := compiler_find_struct(s, type_name)
    if struct_id < 0 { return compiler_fail(s, "drop receiver type is not declared: " + type_name) }
    s = compiler_next(s)
    s = compiler_expect(s, "*")
    receiver := s.token
    if !compiler_ident(receiver) { return compiler_fail(s, "expected drop receiver name") }
    s = compiler_next(s)
    s = compiler_expect(s, ")")
    if s.token != "drop" { return compiler_fail(s, "only drop receiver methods are supported in no-GC compiler subset") }
    if s.struct_custom_drops[struct_id] != 0 { return compiler_fail(s, "duplicate drop method for type: " + type_name) }
    s = compiler_next(s)
    s = compiler_expect(s, "(")
    if s.token != ")" { return compiler_fail(s, "drop method must not have parameters") }
    s = compiler_expect(s, ")")
    if s.token != "{" { return compiler_fail(s, "drop method must not return a value") }
    return compiler_parse_drop_body(s, type_name, struct_id, receiver)
}

func compiler_parse_drop_impl(compiler_state initial) compiler_state {
    s := initial
    s = compiler_expect(s, "impl")
    if s.token != "Drop" { return compiler_fail(s, "only Drop impl blocks are supported in no-GC compiler subset") }
    s = compiler_next(s)
    s = compiler_expect(s, "for")
    if !compiler_is_struct_type(s.token) { return compiler_fail(s, "Drop impl type must be an owned struct") }
    type_name := s.token
    struct_id := compiler_find_struct(s, type_name)
    if struct_id < 0 { return compiler_fail(s, "Drop impl type is not declared: " + type_name) }
    if s.struct_custom_drops[struct_id] != 0 { return compiler_fail(s, "duplicate drop method for type: " + type_name) }
    s = compiler_next(s)
    s = compiler_expect(s, "{")
    s = compiler_expect(s, "func")
    if s.token != "drop" { return compiler_fail(s, "Drop impl must define func drop") }
    s = compiler_next(s)
    s = compiler_expect(s, "(")
    if s.token != type_name { return compiler_fail(s, "Drop impl receiver type mismatch") }
    s = compiler_next(s)
    s = compiler_expect(s, "*")
    receiver := s.token
    if !compiler_ident(receiver) { return compiler_fail(s, "expected drop receiver name") }
    s = compiler_next(s)
    s = compiler_expect(s, ")")
    if s.token != "{" { return compiler_fail(s, "drop method must not return a value") }
    s = compiler_parse_drop_body(s, type_name, struct_id, receiver)
    if s.error != "" { return s }
    s = compiler_expect(s, "}")
    return s
}

func compiler_parse_drop_body(compiler_state initial, string type_name, int struct_id, string receiver) compiler_state {
    s := initial
    s.struct_custom_drops[struct_id] = 1
    s = compiler_expect(s, "{")
    s.code = s.code + "static void compiler_drop_user_" + type_name + "(S_" + type_name + " *" + receiver + ")\n{\n(void)" + receiver + ";\n"
    for s.error == "" && s.token != "}" && s.token != "" {
        if s.token == "println" {
            s = compiler_expect(compiler_next(s), "(")
            if !compiler_is_string_literal(s.token) { return compiler_fail(s, "drop println currently expects a string literal") }
            message := s.token
            s = compiler_next(s)
            s = compiler_expect(s, ")")
            s = compiler_optional_semicolon(s)
            s.code = s.code + "fputs(" + message + ", stdout);\nfputc('\\n', stdout);\n"
        } else if s.token == "assert" {
            s = compiler_expect(compiler_next(s), "(")
            s = compiler_expression(s, 1)
            if s.value_kind != 1 { return compiler_fail(s, "drop assert requires an integer") }
            s = compiler_expect(s, ")")
            s = compiler_optional_semicolon(s)
            s.code = s.code + "compiler_assert(" + s.value + ");\n"
        } else {
            return compiler_subset_fail(s, "drop method body currently supports println/assert only")
        }
    }
    s = compiler_expect(s, "}")
    s.code = s.code + "}\n"
    s
}

func compiler_emit_default_drop_hooks(compiler_state initial) compiler_state {
    s := initial
    i := 0
    for i < s.struct_count {
        if s.struct_custom_drops[i] == 0 {
            name := s.struct_names[i]
            s.code = s.code + "static void compiler_drop_user_" + name + "(S_" + name + " *value) { (void)value; }\n"
        }
        i = i + 1
    }
    s
}

func compiler_parse_function_like(compiler_state initial) compiler_state {
    s := initial
    look := compiler_next(s)
    if look.token == "(" { return compiler_parse_receiver_method(s) }
    compiler_parse_helper(s)
}

func compiler_compile(string source) compiler_state {
    names := ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""];
    kinds := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    live := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    roots := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    parents := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    field_state := roots
    field_borrow_state := roots
    nested_field_state := roots
    nested_field_borrow_state := roots
    field_state_index := 0
    while field_state_index < len(field_state) {
        field_state[field_state_index] = 1
        field_borrow_state[field_state_index] = 0
        nested_field_state[field_state_index] = 1
        nested_field_borrow_state[field_state_index] = 0
        field_state_index = field_state_index + 1
    }
    loan_fields := roots
    loan_parent_fields := roots
    array_lengths := roots
    struct_ids := roots
    function_names := ["", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]; 
    function_counts := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_returns := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_return_params := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    method_names := ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""];
    method_structs := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    method_returns := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_starts := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_param_kinds := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_param_structs := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_return_structs := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    struct_names := ["", "", "", "", "", "", "", ""];
    struct_field_lefts := ["", "", "", "", "", "", "", ""];
    struct_field_rights := ["", "", "", "", "", "", "", ""];
    struct_field_left_kinds := [0, 0, 0, 0, 0, 0, 0, 0];
    struct_field_right_kinds := [0, 0, 0, 0, 0, 0, 0, 0];
    struct_field_names := ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""];
    struct_field_kinds := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    struct_field_structs := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    struct_field_starts := [0, 0, 0, 0, 0, 0, 0, 0];
    struct_field_counts := [0, 0, 0, 0, 0, 0, 0, 0];
    struct_custom_drops := [0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "#include \"compiler_runtime.h\"\n", names: names, kinds: kinds, live: live, roots: roots, parents: parents, loan_fields: loan_fields, loan_parent_fields: loan_parent_fields, array_lengths: array_lengths, struct_ids: struct_ids, field_state: field_state, field_borrow_state: field_borrow_state, nested_field_state: nested_field_state, nested_field_borrow_state: nested_field_borrow_state, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, value_parent_field: -1, value_array_length: 0, value_struct_id: -1, new_borrow: false, function_names: function_names, function_counts: function_counts, function_returns: function_returns, function_return_params: function_return_params, function_starts: function_starts, function_param_kinds: function_param_kinds, function_param_structs: function_param_structs, function_return_structs: function_return_structs, function_param_total: 0, function_count: 0, struct_names: struct_names, struct_field_lefts: struct_field_lefts, struct_field_rights: struct_field_rights, struct_field_left_kinds: struct_field_left_kinds, struct_field_right_kinds: struct_field_right_kinds, struct_field_names: struct_field_names, struct_field_kinds: struct_field_kinds, struct_field_structs: struct_field_structs, struct_field_starts: struct_field_starts, struct_field_counts: struct_field_counts, struct_custom_drops: struct_custom_drops, struct_count: 0, function_name: "", function_main: false, method_names: method_names, method_structs: method_structs, method_returns: method_returns, method_count: 0 }
    s = compiler_next(s)
    s = compiler_expect(s, "package")
    if !compiler_ident(s.token) { return compiler_fail(s, "expected package name") }
    s = compiler_next(s)
    for s.token == "." {
        s = compiler_next(s)
        if !compiler_ident(s.token) { return compiler_fail(s, "expected package path component") }
        s = compiler_next(s)
    }
    if s.token == ";" { s = compiler_next(s) }
    while s.token == "use" || s.token == "import" {
        return compiler_subset_fail(s, "imports and multi-package resolution")
    }
    while s.token == "struct" {
        s = compiler_parse_struct_decl(s)
        if s.error != "" { return s }
    }
    if s.token != "func" && s.token != "impl" {
        string unsupported = compiler_unsupported_token_message(s.token)
        if unsupported != "" { return compiler_subset_fail(s, unsupported) }
    }
    for s.token == "func" || s.token == "impl" {
        if s.token == "impl" {
            s = compiler_parse_drop_impl(s)
            if s.error != "" { return s }
        } else {
            look := compiler_next(s)
            if look.token == "main" {
                break
            }
            s = compiler_parse_function_like(s)
            if s.error != "" { return s }
        }
    }
    s = compiler_emit_default_drop_hooks(s)
    s = compiler_expect(s, "func")
    s = compiler_expect(s, "main")
    s = compiler_expect(s, "(")
    s = compiler_expect(s, ")")
    s.return_kind = 0
    if s.token == "int" {
        s.return_kind = 1
        s = compiler_next(s)
    }
    s.count = 0
    s.depth = 0
    s.loop_floor = -1
    s.loop_cleanup = -1
    s.terminated = 0
    s.function_name = "main"
    s.function_main = true
    s.code = s.code + "int main(void)\n{\n"
    s = compiler_block(s)
    s.code = s.code + "return compiler_finish(0);\n}\n"
    if s.token != "" { s = compiler_fail(s, "unexpected declaration after main") }
    return s
}

func main() {
    args := host_args()
    if len(args) != 4 || args[1] != "--emit-c" {
        eprintln("usage: s_compiler --emit-c input.s output.c")
        return 2
    }
    string source = __host_read_to_string(args[2])
    if source == "" { eprintln("compiler: empty or unreadable input"); return 1 }
    result := compiler_compile(source)
    if result.error != "" { eprintln(result.error); return 1 }
    if __host_write_text_file(args[3], result.code) != 0 { eprintln("compiler: cannot write output"); return 1 }
    return 0
}