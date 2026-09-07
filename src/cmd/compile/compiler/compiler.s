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
    bool new_borrow
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

func compiler_next(initial* compiler_state) compiler_state {
    s := *initial
    if s.error != "" { return s }
    int n = len(s.source)
    eprintln("trace next a")
    for s.pos < n {
        string c = __host_char_at(s.source, s.pos)
        eprintln("trace next b")
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
    eprintln("trace next c")
    int start = s.pos
    string c = __host_char_at(s.source, s.pos)
    eprintln("trace next d")
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
        } else if c != "(" && c != ")" && c != "{" && c != "}" && c != ";" && c != "+" && c != "-" && c != "*" && c != "/" && c != "%" && c != "&" && c != "=" && c != "!" && c != "<" && c != ">" {
            return compiler_fail(s, "unsupported token: " + c)
        }
    }
    s.token = "" + __host_slice(s.source, start, s.pos)
    eprintln("trace next e")
    return s
}

func compiler_expect(compiler_state initial, string token) compiler_state {
    s := initial
    if s.token != token { return compiler_fail(s, "expected '" + token + "', found '" + s.token + "'") }
    return compiler_next(&s)
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
    s.new_borrow = false
    if t == "(" {
        s = compiler_expression(compiler_next(&s), 1)
        return compiler_expect(s, ")")
    }
    if t == "-" || t == "!" {
        s = compiler_atom(compiler_next(&s))
        if s.value_kind != 1 { return compiler_fail(s, "unary operator requires an integer") }
        if t == "-" { s.value = "compiler_sub(0," + s.value + ")" }
        else { s.value = "(!(" + s.value + "))" }
        s.value_slot = -1
        return s
    }
    if t == "&" {
        s = compiler_next(&s)
        int kind = 3
        if s.token == "mut" { kind = 4; s = compiler_next(&s) }
        bool reborrow = s.token == "*"
        if reborrow { s = compiler_next(&s) }
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
        s = compiler_next(&s)
        s.value = compiler_var(slot)
        s.value_kind = kind
        s.value_slot = root
        s.new_borrow = true
        return s
    }
    if t == "*" {
        s = compiler_next(&s)
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] < 2 { return compiler_fail(s, "dereference requires a box or reference") }
        if s.kinds[slot] >= 3 && compiler_child_conflict(s, slot, false) { return compiler_fail(s, "cannot read reference during a mutable reborrow") }
        if s.kinds[slot] == 2 && compiler_conflict(s, slot, false) { return compiler_fail(s, "owner cannot be read during a mutable borrow") }
        s = compiler_next(&s)
        s.value = "(*" + compiler_var(slot) + ")"
        s.value_kind = 1
        s.value_slot = -1
        return s
    }
    if t == "box" {
        s = compiler_expect(compiler_next(&s), "(")
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "box requires an integer") }
        s = compiler_expect(s, ")")
        s.value = "compiler_box(" + s.value + ")"
        s.value_kind = 2
        s.value_slot = -1
        return s
    }
    if t == "live_allocations" {
        s = compiler_expect(compiler_next(&s), "(")
        s = compiler_expect(s, ")")
        s.value = "compiler_live()"
        s.value_kind = 1
        return s
    }
    if t == "true" || t == "false" {
        s.value = "0"
        if t == "true" { s.value = "1" }
        s.value_kind = 1
        return compiler_next(&s)
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
        return compiler_next(&s)
    }
    int slot = compiler_find(s, t)
    s = compiler_available(s, slot)
    if s.error != "" { return s }
    s.value = compiler_var(slot)
    s.value_kind = s.kinds[slot]
    s.value_slot = slot
    return compiler_next(&s)
}

func compiler_expression(compiler_state initial, int minimum) compiler_state {
    s := initial
    s = compiler_atom(s)
    for s.error == "" && compiler_precedence(s.token) >= minimum {
        string op = s.token
        int precedence = compiler_precedence(op)
        string left = s.value
        if s.value_kind != 1 { return compiler_fail(s, "binary operator requires integers") }
        s = compiler_expression(compiler_next(&s), precedence + 1)
        if s.value_kind != 1 { return compiler_fail(s, "binary operator requires integers") }
        string helper = ""
        if op == "+" { helper = "compiler_add" }
        if op == "-" { helper = "compiler_sub" }
        if op == "*" { helper = "compiler_mul" }
        if op == "/" { helper = "compiler_div" }
        if op == "%" { helper = "compiler_mod" }
        if helper != "" { s.value = helper + "(" + left + "," + s.value + ")" }
        else { s.value = "(" + left + op + s.value + ")" }
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
    if !declaration && s.value_kind >= 3 { return compiler_fail(s, "reference reassignment is not supported") }
    string rhs = s.value
    int origin = s.value_slot
    if s.value_kind == 2 {
        if !declaration {
            if compiler_conflict(s, slot, true) { return compiler_fail(s, "cannot overwrite borrowed owner") }
            if s.loop_floor >= 0 && slot < s.loop_floor { return compiler_fail(s, "cannot replace an outer owner inside a loop") }
        }
        if origin == slot { return compiler_fail(s, "self move is not supported") }
        if origin >= 0 {
            s = compiler_consume(s, origin)
            rhs = "compiler_move(&" + compiler_var(origin) + ")"
        }
    }
    int parent = s.value_parent
    if s.value_kind >= 3 && !s.new_borrow {
        if s.value_kind == 4 { return compiler_fail(s, "mutable reference copying is not supported; create a reborrow") }
        parent = s.parents[origin]
        origin = s.roots[origin]
    }
    string ctype = "int64_t "
    if s.value_kind >= 2 { ctype = "int64_t *" }
    if s.value_kind == 3 { ctype = "const int64_t *" }
    if !declaration { ctype = "" }
    if !declaration && s.value_kind == 2 {
        s.code = s.code + "{ int64_t *compiler_new = " + rhs + ";\ncompiler_drop(&" + compiler_var(slot) + ");\n" + compiler_var(slot) + " = compiler_new; }\n"
    } else {
        s.code = s.code + ctype + compiler_var(slot) + " = " + rhs + ";\n"
    }
    s.code = s.code + "(void)" + compiler_var(slot) + ";\n"
    s.names[slot] = name
    s.kinds[slot] = s.value_kind
    s.live[slot] = 1
    s.roots[slot] = -1
    s.parents[slot] = -1
    if s.value_kind >= 3 { s.roots[slot] = origin; s.parents[slot] = parent }
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
        s = compiler_expression(compiler_next(&s), 1)
        if s.value_kind != 1 { return compiler_fail(s, "condition requires an integer") }
        s.code = s.code + "if (" + s.value + ")\n"
        before := s
        yes := compiler_block(s)
        if yes.error != "" { return yes }
        no := before
        no.pos = yes.pos; no.line = yes.line; no.token = yes.token; no.code = yes.code
        if no.token == "else" {
            no = compiler_next(&no)
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
        no.terminated = both_terminated
        return no
    }
    if s.token == "while" {
        s = compiler_expression(compiler_next(&s), 1)
        if s.value_kind != 1 { return compiler_fail(s, "condition requires an integer") }
        s.code = s.code + "while (" + s.value + ")\n"
        int old_floor = s.loop_floor
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
        s = compiler_expression(compiler_next(&s), 1)
        if s.value_kind != 1 { return compiler_fail(s, "return requires an integer; references and owners cannot escape this subset") }
        s = compiler_expect(s, ";")
        s.code = s.code + "{ int64_t compiler_result = " + s.value + ";\n" + compiler_cleanup(s, 0) + "return compiler_finish(compiler_result); }\n"
        s.terminated = 1
        return s
    }
    if s.token == "break" || s.token == "continue" {
        string op = s.token
        if s.loop_floor < 0 { return compiler_fail(s, "loop control outside a loop") }
        s = compiler_expect(compiler_next(&s), ";")
        s.code = s.code + compiler_cleanup(s, s.loop_cleanup) + op + ";\n"
        s.terminated = 1
        return s
    }
    if s.token == "drop" {
        s = compiler_expect(compiler_next(&s), "(")
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] == 2 {
            s = compiler_consume(s, slot)
            s.code = s.code + "compiler_drop(&" + compiler_var(slot) + ");\n"
        } else if s.kinds[slot] >= 3 {
            if compiler_child_conflict(s, slot, true) { return compiler_fail(s, "cannot drop reference with a live reborrow") }
            if s.loop_floor >= 0 && slot < s.loop_floor { return compiler_fail(s, "cannot end an outer borrow inside a loop") }
            s.live[slot] = 0
        } else { return compiler_fail(s, "drop requires an owner or reference") }
        s = compiler_expect(compiler_next(&s), ")")
        return compiler_expect(s, ";")
    }
    if s.token == "assert" {
        s = compiler_expect(compiler_next(&s), "(")
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "assert requires an integer") }
        s = compiler_expect(s, ")")
        s = compiler_expect(s, ";")
        s.code = s.code + "compiler_assert(" + s.value + ");\n"
        return s
    }
    if s.token == "*" {
        s = compiler_next(&s)
        int slot = compiler_find(s, s.token)
        s = compiler_available(s, slot)
        if s.error != "" { return s }
        if s.kinds[slot] != 2 && s.kinds[slot] != 4 { return compiler_fail(s, "write requires an owner or mutable reference") }
        if s.kinds[slot] == 4 && compiler_child_conflict(s, slot, true) { return compiler_fail(s, "cannot write reference with a live reborrow") }
        if s.kinds[slot] == 2 && compiler_conflict(s, slot, true) { return compiler_fail(s, "cannot write borrowed owner") }
        s = compiler_expect(compiler_next(&s), "=")
        s = compiler_expression(s, 1)
        if s.value_kind != 1 { return compiler_fail(s, "box write requires an integer") }
        s = compiler_expect(s, ";")
        s.code = s.code + "*" + compiler_var(slot) + " = " + s.value + ";\n"
        return s
    }
    string name = s.token
    s = compiler_next(&s)
    bool declaration = s.token == ":="
    if !declaration && s.token != "=" { return compiler_fail(s, "expected := or =; unsupported statement") }
    s = compiler_expression(compiler_next(&s), 1)
    s = compiler_bind(s, name, declaration)
    return compiler_expect(s, ";")
}

func compiler_compile(string source) compiler_state {
    eprintln("trace compile a")
    names := ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""];
    kinds := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    live := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    roots := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    parents := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    s := compiler_state { source: source, pos: 0, line: 1, token: "", error: "", code: "#include \"compiler_runtime.h\"\nint main(void)\n", names: names, kinds: kinds, live: live, roots: roots, parents: parents, count: 0, loop_floor: -1, loop_cleanup: -1, depth: 0, expr_depth: 0, terminated: 0, value: "", value_kind: 0, value_slot: -1, value_parent: -1, new_borrow: false }
    eprintln("trace compile b")
    s = compiler_next(&s)
    s = compiler_expect(s, "package")
    if !compiler_ident(s.token) { return compiler_fail(s, "expected package name") }
    s = compiler_next(&s)
    if s.token == ";" { s = compiler_next(&s) }
    s = compiler_expect(s, "func")
    s = compiler_expect(s, "main")
    s = compiler_expect(s, "(")
    s = compiler_expect(s, ")")
    s = compiler_expect(s, "int")
    s.code = s.code + "{\n"
    s = compiler_block(s)
    s.code = s.code + "return compiler_finish(0);\n}\n"
    if s.token != "" { s = compiler_fail(s, "only one main function is supported; imports and extern declarations are forbidden") }
    return s
}

func main() {
    eprintln("trace main a")
    args := host_args()
    eprintln("trace main b")
    if len(args) != 4 || args[1] != "--emit-c" {
        eprintln("usage: s_compiler --emit-c input.s output.c")
        return 2
    }
    string source = __host_read_to_string(args[2])
    eprintln("trace main c")
    if source == "" { eprintln("compiler: empty or unreadable input"); return 1 }
    eprintln("trace main d")
    result := compiler_compile(source)
    eprintln("trace main e")
    if result.error != "" { eprintln(result.error); return 1 }
    if __host_write_text_file(args[3], result.code) != 0 { eprintln("compiler: cannot write output"); return 1 }
    return 0
}
