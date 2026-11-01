package compile.internal

struct switch_plan {
    string kind
    int case_count
    bool has_default
    bool dense
    string lowering
}

func walk_switch_module_name() string {
    "walk/switch.s"
}

func walk_switch_module_apply() int {
    0
}

func walk_switch_plan(string kind, int case_count, int table_size, bool has_default) switch_plan {
    switch_plan {
        kind: kind,
        case_count: case_count,
        has_default: has_default,
        dense: switch_is_dense(case_count, table_size),
        lowering: switch_lowering(kind, case_count, table_size),
    }
}

func switch_is_dense(int case_count, int table_size) bool {
    table_size > 0 && case_count * 4 >= table_size
}

func switch_lowering(string kind, int case_count, int table_size) string {
    if kind == "type" {
        return "type-switch"
    }
    if switch_is_dense(case_count, table_size) {
        return "jump-table"
    }
    if case_count > 4 {
        return "binary-search"
    }
    "linear-search"
}

func switch_has_fallthrough(string terminator) bool {
    terminator == "fallthrough"
}
