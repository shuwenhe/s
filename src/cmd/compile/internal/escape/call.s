package compile.internal.escape

import (
    "compile.internal.base"
    "compile.internal.ir"
)

const escape_none = 0
const escape_func = 1
const escape_global = 2
const escape_heap = 3
const nil = 0

func classify_call_escape(string callee, int arg_count, bool returns_pointer) int {
    if callee == "box" || callee == "make" || callee == "new" {
        return escape_heap
    }
    if returns_pointer {
        return escape_func
    }
    if arg_count > 6 {
        return escape_func
    }
    escape_none
}

func record_call_escape(escape_analysis analysis, int call_id, string callee, int arg_count, bool returns_pointer) int {
    level := classify_call_escape(callee, arg_count, returns_pointer)
    level
}
