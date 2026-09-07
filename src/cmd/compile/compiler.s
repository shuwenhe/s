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
    int[] field_left_live
    int[] field_right_live
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
    int function_count
    int function_param_total
    string function_name
    bool function_main
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
    if compiler_alpha(c) || compiler_digit(c) {
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
        } else if c != "(" && c != ")" && c != "{" && c != "}" && c != ";" && c != "," && c != "." && c != "+" && c != "-" && c != "*" && c != "/" && c != "%" && c != "&" && c != "=" && c != "!" && c != "<" && c != ">" {
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

func compiler_find_func(compiler_state initial, string name) int {
    s := initial
    int i = s.function_count - 1
    for i >= 0 {
        if s.function_names[i] == name { return i }
        i = i - 1
    }
    return -1
}

func compiler_conflict(compiler_state initial, int owner, bool exclusive) bool {
    s := initial
    int i = 0
    for i < s.count {
        if s.live[i] != 0 && s.roots[i] == owner && (s.kinds[i] == 4 || (exclusive && s.kinds[i] == 3)) { return true }
        i = i + 1
    }
    return false
}

func compiler_child_conflict(compiler_state initial, int parent, bool exclusive) bool {
    s := initial
    int i = 0
    for i < s.count {
        if s.live[i] != 0 && s.parents[i] == parent && (s.kinds[i] == 4 || (exclusive && s.kinds[i] == 3)) { return true }
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
    if s.loop_floor >= 0 && slot < s.loop_floor { return compiler_fail(s, "cannot consume an outer owner inside a loop") }
    s.live[slot] = 0
    return s
}

func compiler_cleanup(compiler_state initial, int floor) string {
    s := initial
    string code = ""
    int i = s.count - 1
    for i >= floor {
        if s.kinds[i] == 2 { code = code + "compiler_drop(&" + compiler_var(i) + ");\n" }
        if s.kinds[i] == 5 { code = code + "compiler_pair_drop(&" + compiler_var(i) + ");\n" }
        i = i - 1
    }
    return code
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
    s.new_borrow = false
    if t == "(" {
        s = compiler_expression(compiler_next(s), 1)
        return compiler_expect(s, ")")
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
        int root = slot
        if reborrow {
            if s.kinds[slot] < 3 { return compiler_fail(s, "reborrow requires a reference") }
            if kind == 4 && s.kinds[slot] == 3 { return compiler_fail(s, "cannot mutably reborrow a shared reference") }
            if compiler_child_conflict(s, slot, kind == 4) { return compiler_fail(s, "conflicting reborrow: " + s.names[slot]) }
            root = s.roots[slot]
            s.value_parent = slot
        } else {
            if s.kinds[slot] != 2 { return compiler_fail(s, "borrow requires an owned box; use &*reference to reborrow") }
            if compiler_conflict(s, slot, kind == 4) { return compiler_fail(s, "conflicting borrow: " + s.names[slot]) }
        }
        s = compiler_next(s)
        s.value = compiler_var(slot)
        s.value_kind = kind
        s.value_slot = root
        s.new_borrow = true
        return s
    }
    if t == "*" {
        s = compiler_next(s)
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] < 2 { return compiler_fail(s, "dereference requires a box or reference") }
        int field = -1
        s = compiler_next(s)
        if s.token == "." {
            s = compiler_next(s)
            if s.token == "left" { field = 0 }
            if s.token == "right" { field = 1 }
            if field < 0 { return compiler_fail(s, "invalid pair field dereference") }
            if s.kinds[slot] != 5 { return compiler_fail(s, "invalid pair field dereference") }
            if field == 0 && s.field_left_live[slot] != 1 { return compiler_fail(s, "use of moved pair field") }
            if field == 1 && s.field_right_live[slot] != 1 { return compiler_fail(s, "use of moved pair field") }
            s.value = "(*" + compiler_var(slot) + "->" + compiler_field_name(field) + ")"
            s = compiler_next(s)
        } else {
            s.value = "(*" + compiler_var(slot) + ")"
        }
        if s.kinds[slot] >= 3 && s.kinds[slot] <= 4 && compiler_child_conflict(s, slot, false) { return compiler_fail(s, "cannot read reference during a mutable reborrow") }
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
    if t == "pair" {
        s = compiler_expect(compiler_next(s), "(")
        s = compiler_expression(s, 1)
        if s.value_kind != 2 { return compiler_fail(s, "pair left field requires an owner") }
        string left = s.value
        if s.value_slot >= 0 {
            int origin = s.value_slot
            if s.value_field >= 0 {
                if compiler_conflict(s, origin, true) { return compiler_fail(s, "cannot move borrowed pair field") }
                if s.value_field == 0 { s.field_left_live[origin] = 0 }
                else { s.field_right_live[origin] = 0 }
                left = "compiler_pair_move_field(" + compiler_var(origin) + "," + compiler_number(s.value_field) + ")"
            } else {
                s = compiler_consume(s, origin)
                left = "compiler_move(&" + compiler_var(origin) + ")"
            }
        }
        s = compiler_expect(s, ",")
        s = compiler_expression(s, 1)
        if s.value_kind != 2 { return compiler_fail(s, "pair right field requires an owner") }
        string right = s.value
        if s.value_slot >= 0 {
            int origin = s.value_slot
            if s.value_field >= 0 {
                if compiler_conflict(s, origin, true) { return compiler_fail(s, "cannot move borrowed pair field") }
                if s.value_field == 0 { s.field_left_live[origin] = 0 }
                else { s.field_right_live[origin] = 0 }
                right = "compiler_pair_move_field(" + compiler_var(origin) + "," + compiler_number(s.value_field) + ")"
            } else {
                s = compiler_consume(s, origin)
                right = "compiler_move(&" + compiler_var(origin) + ")"
            }
        }
        s = compiler_expect(s, ")")
        s.value = "compiler_pair_make(" + left + "," + right + ")"
        s.value_kind = 5
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
            if s.value_kind < 1 || s.value_kind > 5 { return compiler_fail(s, "function arguments require integers, owners, pairs or references") }
            if arg >= s.function_counts[function_index] { return compiler_fail(s, "too many function arguments") }
            int expected = s.function_param_kinds[s.function_starts[function_index] + arg]
            if s.value_kind != expected { return compiler_fail(s, "function argument type mismatch") }
            string argument = s.value
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
                if s.function_returns[function_index] >= 3 && s.function_returns[function_index] <= 4 && arg == s.function_return_params[function_index] {
                    returned_loan_slot = s.count
                }
                s.count = s.count + 1
            }
            if expected == 2 || expected == 5 {
                if s.value_slot >= 0 {
                    int origin = s.value_slot
                    s = compiler_consume(s, origin)
                    if expected == 5 { argument = "compiler_pair_move(&" + compiler_var(origin) + ")" }
                    else { argument = "compiler_move(&" + compiler_var(origin) + ")" }
                }
            }
            string temporary = "s_arg" + call_id + "_" + compiler_number(arg)
            string argument_type = "int64_t "
            if expected == 2 || expected == 4 { argument_type = "int64_t *" }
            if expected == 5 { argument_type = "compiler_pair *" }
            if expected == 3 { argument_type = "const int64_t *" }
            s.code = s.code + argument_type + temporary + ";\n"
            evaluations = evaluations + "(" + temporary + " = " + argument + "),"
            if arg > 0 { args = args + "," }
            args = args + temporary
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
    int slot = compiler_find(s, t)
    s = compiler_available(s, slot)
    if s.error != "" { return s }
    s = compiler_next(s)
    if s.token == "." {
        s = compiler_next(s)
        int field = -1
        if s.token == "left" { field = 0 }
        if s.token == "right" { field = 1 }
        if field < 0 { return compiler_fail(s, "pair has only left and right fields") }
        if s.kinds[slot] != 5 { return compiler_fail(s, "field access requires a pair") }
        if field == 0 && s.field_left_live[slot] != 1 {
            return compiler_fail(s, "use of moved pair field")
        }
        if field == 1 && s.field_right_live[slot] != 1 {
            return compiler_fail(s, "use of moved pair field")
        }
        s.value = compiler_var(slot) + "->" + compiler_field_name(field)
        s.value_kind = 2
        s.value_slot = slot
        s.value_field = field
        s = compiler_next(s)
        return s
    }
    s.value = compiler_var(slot)
    s.value_kind = s.kinds[slot]
    s.value_slot = slot
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
    if declaration && slot >= 0 { return compiler_fail(s, "duplicate or shadowed variable: " + name) }
    if !declaration && slot < 0 { return compiler_fail(s, "assignment to unknown variable: " + name) }
    if !compiler_ident(name) { return compiler_fail(s, "expected variable name") }
    if declaration { slot = s.count }
    if !declaration && s.kinds[slot] != s.value_kind { return compiler_fail(s, "assignment changes variable type") }
    if !declaration && s.value_kind >= 3 && s.value_kind <= 4 { return compiler_fail(s, "reference reassignment is not supported") }
    string rhs = s.value
    int origin = s.value_slot
    if s.value_kind == 2 || s.value_kind == 5 {
        if s.value_field >= 0 {
            if s.kinds[origin] != 5 { return compiler_fail(s, "field move requires a pair") }
            if compiler_conflict(s, origin, true) { return compiler_fail(s, "cannot move borrowed pair field") }
            if s.value_field == 0 { s.field_left_live[origin] = 0 }
            else { s.field_right_live[origin] = 0 }
            rhs = "compiler_pair_move_field(" + compiler_var(origin) + "," + compiler_number(s.value_field) + ")"
            origin = -1
        }
        if !declaration {
            if compiler_conflict(s, slot, true) { return compiler_fail(s, "cannot overwrite borrowed owner") }
            if s.loop_floor >= 0 && slot < s.loop_floor { return compiler_fail(s, "cannot replace an outer owner inside a loop") }
        }
        if origin == slot { return compiler_fail(s, "self move is not supported") }
        if origin >= 0 {
            s = compiler_consume(s, origin)
            if s.value_kind == 5 { rhs = "compiler_pair_move(&" + compiler_var(origin) + ")" }
            else { rhs = "compiler_move(&" + compiler_var(origin) + ")" }
        }
    }
    int parent = s.value_parent
    if s.value_kind >= 3 && s.value_kind <= 4 && !s.new_borrow {
        if s.value_kind == 4 { return compiler_fail(s, "mutable reference copying is not supported; create a reborrow") }
        parent = s.parents[origin]
        origin = s.roots[origin]
    }
    string ctype = "int64_t "
    if s.value_kind == 5 { ctype = "compiler_pair *" }
    else if s.value_kind >= 2 { ctype = "int64_t *" }
    if s.value_kind == 3 { ctype = "const int64_t *" }
    if !declaration { ctype = "" }
    if !declaration && (s.value_kind == 2 || s.value_kind == 5) {
        string replacement_type = "int64_t *"
        string replacement_drop = "compiler_drop"
        if s.value_kind == 5 { replacement_type = "compiler_pair *"; replacement_drop = "compiler_pair_drop" }
        s.code = s.code + "{ " + replacement_type + "compiler_new = " + rhs + ";\n" + replacement_drop + "(&" + compiler_var(slot) + ");\n" + compiler_var(slot) + " = compiler_new; }\n"
    } else {
        s.code = s.code + ctype + compiler_var(slot) + " = " + rhs + ";\n"
    }
    s.code = s.code + "(void)" + compiler_var(slot) + ";\n"
    s.names[slot] = name
    s.kinds[slot] = s.value_kind
    s.live[slot] = 1
    s.roots[slot] = -1
    s.parents[slot] = -1
    if s.value_kind == 5 { s.field_left_live[slot] = 1; s.field_right_live[slot] = 1 }
    if s.value_kind >= 3 && s.value_kind <= 4 { s.roots[slot] = origin; s.parents[slot] = parent }
    if declaration { s.count = s.count + 1 }
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
    if s.token == "return" {
        s = compiler_expression(compiler_next(s), 1)
        if s.value_kind != s.return_kind { return compiler_fail(s, "return type mismatch") }
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
            if s.value_slot >= 0 {
                int origin = s.value_slot
                s = compiler_consume(s, origin)
                s.value = "compiler_move(&" + compiler_var(origin) + ")"
            }
        } else if s.value_kind == 3 { result_type = "const int64_t *" }
        else if s.value_kind == 4 { result_type = "int64_t *" }
        else if s.value_kind == 5 {
            result_type = "compiler_pair *"
            if s.value_slot >= 0 {
                int origin = s.value_slot
                s = compiler_consume(s, origin)
                s.value = "compiler_pair_move(&" + compiler_var(origin) + ")"
            }
        }
        s = compiler_expect(s, ";")
        string finish = "return compiler_result;"
        if s.function_main { finish = "return compiler_finish(compiler_result);" }
        s.code = s.code + "{ " + result_type + "compiler_result = " + s.value + ";\n" + compiler_cleanup(s, 0) + finish + " }\n"
        s.terminated = 1
        return s
    }
    if s.token == "break" || s.token == "continue" {
        string op = s.token
        if s.loop_floor < 0 { return compiler_fail(s, "loop control outside a loop") }
        s = compiler_expect(compiler_next(s), ";")
        s.code = s.code + compiler_cleanup(s, s.loop_cleanup) + op + ";\n"
        s.terminated = 1
        return s
    }
    if s.token == "drop" {
        s = compiler_expect(compiler_next(s), "(")
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] == 2 {
            s = compiler_consume(s, slot)
            s.code = s.code + "compiler_drop(&" + compiler_var(slot) + ");\n"
        } else if s.kinds[slot] == 5 {
            s = compiler_consume(s, slot)
            s.code = s.code + "compiler_pair_drop(&" + compiler_var(slot) + ");\n"
        } else if s.kinds[slot] >= 3 {
            if compiler_child_conflict(s, slot, true) { return compiler_fail(s, "cannot drop reference with a live reborrow") }
            if s.loop_floor >= 0 && slot < s.loop_floor { return compiler_fail(s, "cannot end an outer borrow inside a loop") }
            s.live[slot] = 0
        } else { return compiler_fail(s, "drop requires an owner or reference") }
        s = compiler_expect(compiler_next(s), ")")
        return compiler_expect(s, ";")
    }
    if s.token == "assert" {
        s = compiler_expect(compiler_next(s), "(")
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "assert requires an integer") }
        s = compiler_expect(s, ")")
        s = compiler_expect(s, ";")
        s.code = s.code + "compiler_assert(" + s.value + ");\n"
        return s
    }
    if s.token == "*" {
        s = compiler_next(s)
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] != 2 && s.kinds[slot] != 4 { return compiler_fail(s, "write requires an owner or mutable reference") }
        if s.kinds[slot] == 4 && compiler_child_conflict(s, slot, true) { return compiler_fail(s, "cannot write reference with a live reborrow") }
        if s.kinds[slot] == 2 && compiler_conflict(s, slot, true) { return compiler_fail(s, "cannot write borrowed owner") }
        s = compiler_expect(compiler_next(s), "=")
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "box write requires an integer") }
        s = compiler_available(s, slot)
        s = compiler_expect(s, ";")
        s.code = s.code + "*" + compiler_var(slot) + " = " + s.value + ";\n"
        return s
    }
    string name = s.token
    s = compiler_next(s)
    bool declaration = s.token == ":="
    if !declaration && s.token != "=" { return compiler_fail(s, "expected := or =; unsupported statement") }
    s = compiler_expression(compiler_next(s), 1)
    s = compiler_bind(s, name, declaration)
    return compiler_expect(s, ";")
}

func compiler_parse_helper(compiler_state initial) compiler_state {
    s := initial
    s = compiler_expect(s, "func")
    string name = s.token
    if !compiler_ident(name) || name == "main" { return compiler_fail(s, "expected helper function name") }
    s = compiler_next(s)
    s = compiler_expect(s, "(")
    int param_count = 0
    s.count = 0
    for s.token != ")" && s.token != "" {
        if param_count > 0 { s = compiler_expect(s, ",") }
        int kind = 0
        if s.token == "int" { kind = 1 }
        else if s.token == "box" { kind = 2 }
        else if s.token == "ref" { kind = 3 }
        else if s.token == "mutref" { kind = 4 }
        else if s.token == "pair" { kind = 5 }
        else { return compiler_fail(s, "function parameters require int, box, ref, mutref or pair") }
        s = compiler_next(s)
        string param = s.token
        if !compiler_ident(param) { return compiler_fail(s, "expected parameter name") }
        if param_count >= 16 { return compiler_fail(s, "too many function parameters") }
        s.names[param_count] = param
        s.kinds[param_count] = kind
        param_count = param_count + 1
        s = compiler_next(s)
    }
    s = compiler_expect(s, ")")
    s.return_kind = 1
    if s.token == "box" { s.return_kind = 2 }
    else if s.token == "ref" { s.return_kind = 3 }
    else if s.token == "mutref" { s.return_kind = 4 }
    else if s.token == "pair" { s.return_kind = 5 }
    else if s.token != "int" { return compiler_fail(s, "function return type must be int, box, ref, mutref or pair") }
    s = compiler_next(s)
    s.parameter_count = param_count
    s.return_param = -1

    int start = s.function_param_total
    s.function_names[s.function_count] = name
    s.function_counts[s.function_count] = param_count
    s.function_returns[s.function_count] = s.return_kind
    s.function_return_params[s.function_count] = s.return_param
    s.function_starts[s.function_count] = start
    int pi = 0
    for pi < param_count {
        s.function_param_kinds[s.function_param_total + pi] = s.kinds[pi]
        pi = pi + 1
    }
    s.function_param_total = s.function_param_total + param_count
    s.function_count = s.function_count + 1

    string signature = "static int64_t " + name + "("
    if s.return_kind == 2 || s.return_kind == 4 { signature = "static int64_t *" + name + "(" }
    else if s.return_kind == 5 { signature = "static compiler_pair *" + name + "(" }
    else if s.return_kind == 3 { signature = "static const int64_t *" + name + "(" }
    pi = 0
    for pi < param_count {
        if pi > 0 { signature = signature + ", " }
        if s.kinds[pi] == 2 || s.kinds[pi] == 4 { signature = signature + "int64_t *" }
        else if s.kinds[pi] == 5 { signature = signature + "compiler_pair *" }
        else if s.kinds[pi] == 3 { signature = signature + "const int64_t *" }
        else { signature = signature + "int64_t " }
        signature = signature + "p" + compiler_number(pi)
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
        string ctype = "int64_t "
        if s.kinds[pi] == 2 || s.kinds[pi] == 4 { ctype = "int64_t *" }
        else if s.kinds[pi] == 5 { ctype = "compiler_pair *" }
        else if s.kinds[pi] == 3 { ctype = "const int64_t *" }
        s.code = s.code + ctype + compiler_var(pi) + " = p" + compiler_number(pi) + ";\n"
        s.code = s.code + "(void)" + compiler_var(pi) + ";\n"
        s.live[pi] = 1
        s.roots[pi] = -1
        if s.kinds[pi] >= 3 && s.kinds[pi] <= 4 { s.roots[pi] = pi }
        s.parents[pi] = -1
        if s.kinds[pi] == 5 { s.field_left_live[pi] = 1; s.field_right_live[pi] = 1 }
        s.count = s.count + 1
        pi = pi + 1
    }
    s = compiler_block(s)
    if s.error != "" { return s }
    if s.return_kind != 1 && s.terminated == 0 { return compiler_fail(s, "non-integer function must return on every path") }
    if s.terminated == 0 { s.code = s.code + compiler_cleanup(s, 0) + "return 0;\n" }
    s.code = s.code + "}\n"
    return s
}

func compiler_compile(string source) compiler_state {
    names := ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""];
    kinds := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    live := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    roots := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    parents := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    field_left_live := live
    field_right_live := live
    function_names := ["", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]; 
    function_counts := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_returns := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_return_params := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_starts := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    function_param_kinds := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "#include \"compiler_runtime.h\"\n", names: names, kinds: kinds, live: live, roots: roots, parents: parents, field_left_live: field_left_live, field_right_live: field_right_live, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, value_field: -1, new_borrow: false, function_names: function_names, function_counts: function_counts, function_returns: function_returns, function_return_params: function_return_params, function_starts: function_starts, function_param_kinds: function_param_kinds, function_param_total: 0, function_count: 0, function_name: "", function_main: false }
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
    for s.token == "func" {
        look := compiler_next(s)
        if look.token == "main" {
            break
        }
        s = compiler_parse_helper(s)
        if s.error != "" { return s }
    }
    s = compiler_expect(s, "func")
    s = compiler_expect(s, "main")
    s = compiler_expect(s, "(")
    s = compiler_expect(s, ")")
    s = compiler_expect(s, "int")
    s.count = 0
    s.depth = 0
    s.loop_floor = -1
    s.loop_cleanup = -1
    s.terminated = 0
    s.function_name = "main"
    s.function_main = true
    s.return_kind = 1
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
