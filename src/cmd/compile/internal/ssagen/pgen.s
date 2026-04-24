package compile.internal.ssagen

use std.vec.vec

struct pgen_plan {
    vec[string] lines
    int stack_size
    bool has_split_check
}

func build_pgen_plan(string fn_name, int stack_size, bool need_split_check, bool emit_arginfo, bool emit_wrapinfo) pgen_plan {
    var lines = vec[string]()
    lines.push("TEXT " + fn_name)
    if need_split_check {
        lines.push("split-check")
    }
    lines.push("stack=" + to_string(stack_size))
    if emit_arginfo {
        lines.push("funcdata:arginfo")
    }
    if emit_wrapinfo {
        lines.push("funcdata:wrapinfo")
    }
    pgen_plan {
        lines: lines,
        stack_size: stack_size,
        has_split_check: need_split_check,
    }
}
