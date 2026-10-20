package compile.internal

struct compare_plan {
    string op
    string kind
    string helper
    bool needs_runtime
}

func compare_module_name() string {
    "walk/compare.s"
}

func compare_module_apply() int {
    0
}

func walk_compare_plan(string op, string kind) compare_plan {
    compare_plan {
        op: op,
        kind: kind,
        helper: compare_helper(op, kind),
        needs_runtime: compare_needs_runtime(kind),
    }
}

func compare_needs_runtime(string kind) bool {
    kind == "string" || kind == "interface" || kind == "array" || kind == "struct"
}

func compare_helper(string op, string kind) string {
    if kind == "string" {
        return "cmpstring"
    }
    if kind == "interface" {
        return "ifaceeq"
    }
    if kind == "array" || kind == "struct" {
        return "memequal"
    }
    op
}

func compare_reverse(string op) string {
    if op == "<" { return ">" }
    if op == ">" { return "<" }
    if op == "<=" { return ">=" }
    if op == ">=" { return "<=" }
    op
}
