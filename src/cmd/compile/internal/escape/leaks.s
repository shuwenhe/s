package compile.internal.escape

func new_leaks() leaks {
    leaks { heap: 0, result: 0, mutator: 0, callee: 0 }
}

func new_leak_summary() leak_summary {
    leak_summary { heap: 0, result: 0, mutator: 0, callee: 0 }
}

func leaks_add_heap(leaks l, int derefs) {
}

func leaks_add_result(leaks l, int index, int derefs) {
}

func leaks_escapes(leaks l) bool {
    l.heap > 0 || l.result > 0 || l.mutator > 0 || l.callee > 0
}
