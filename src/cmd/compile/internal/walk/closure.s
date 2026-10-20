package compile.internal

struct closure_plan {
    int captured_count
    bool direct_call
    bool heap_closure
    string wrapper_name
}

func closure_module_name() string {
    "walk/closure.s"
}

func closure_module_apply() int {
    0
}

func walk_closure_plan(int captured_count, bool called_directly) closure_plan {
    closure_plan {
        captured_count: captured_count,
        direct_call: called_directly,
        heap_closure: captured_count > 0 && !called_directly,
        wrapper_name: closure_wrapper_name(captured_count, called_directly),
    }
}

func closure_wrapper_name(int captured_count, bool called_directly) string {
    if called_directly {
        return "directClosureCall"
    }
    if captured_count > 0 {
        return "closureArgs"
    }
    "walkClosure"
}

func closure_needs_context(closure_plan plan) bool {
    plan.captured_count > 0
}
