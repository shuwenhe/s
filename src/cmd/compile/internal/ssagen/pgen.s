package compile.internal.ssagen
use std.slices
struct pgen_plan {
    []string lines
    int stack_size
    bool has_split_check
}

func build_pgen_plan(string fn_name, int stack_size, bool need_split_check, bool emit_arginfo, bool emit_wrapinfo) pgen_plan {
    lines := []string()
    lines = append(lines, "TEXT " + fn_name)
    if need_split_check {
        lines = append(lines, "split-check")
    }
    lines = append(lines, "stack=" + to_string(stack_size))
    if emit_arginfo {
        lines = append(lines, "funcdata:arginfo")
    }
    if emit_wrapinfo {
        lines = append(lines, "funcdata:wrapinfo")
    }
    pgen_plan {
        lines: lines, stack_size stack_size, has_split_check need_split_check,
    }
}
