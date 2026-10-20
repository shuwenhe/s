package compile.internal

struct range_plan {
    string source_kind
    string lowering
    bool needs_iterator
    bool can_clear
}

func range_module_name() string {
    "walk/range.s"
}

func range_module_apply() int {
    0
}

func walk_range_plan(string source_kind) range_plan {
    range_plan {
        source_kind: source_kind,
        lowering: range_lowering(source_kind),
        needs_iterator: source_kind == "map" || source_kind == "chan",
        can_clear: source_kind == "array" || source_kind == "slice" || source_kind == "map",
    }
}

func range_lowering(string source_kind) string {
    if source_kind == "array" || source_kind == "slice" {
        return "index-loop"
    }
    if source_kind == "map" {
        return "map-iterator"
    }
    if source_kind == "chan" {
        return "chan-recv-loop"
    }
    if source_kind == "string" {
        return "string-iter"
    }
    "unknown"
}

func cheap_computable_index(int width) bool {
    width == 1 || width == 2 || width == 4 || width == 8
}
