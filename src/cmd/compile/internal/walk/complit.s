package compile.internal.walk

const literal_init_static = 0
const literal_init_stack = 1
const literal_init_dynamic = 2

struct composite_literal_plan {
    string kind
    int element_count
    bool static_ok
    bool small_slice
    int init_kind
}

func complit_module_name() string {
    "walk/complit.s"
}

func complit_module_apply() int {
    0
}

func walk_composite_literal_plan(string kind, int element_count, bool has_dynamic_value) composite_literal_plan {
    init_kind := literal_init_static
    if has_dynamic_value {
        init_kind = literal_init_dynamic
    }
    composite_literal_plan {
        kind: kind,
        element_count: element_count,
        static_ok: !has_dynamic_value,
        small_slice: kind == "slice" && element_count <= 4,
        init_kind: init_kind,
    }
}

func composite_literal_needs_heap(composite_literal_plan plan) bool {
    plan.kind == "map" || (plan.kind == "slice" && !plan.small_slice)
}

func composite_literal_init_name(int kind) string {
    if kind == literal_init_static { return "static" }
    if kind == literal_init_stack { return "stack" }
    "dynamic"
}
