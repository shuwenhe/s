package compile.internal

struct temp_plan {
    string type_name
    int size
    bool clear
    bool stack_ok
}

func temp_module_name() string {
    "walk/temp.s"
}

func temp_module_apply() int {
    0
}

func stack_temp_plan(string type_name, int size, bool clear) temp_plan {
    temp_plan {
        type_name: type_name,
        size: size,
        clear: clear,
        stack_ok: size >= 0 && size <= 65536,
    }
}

func stack_buf_plan(int length, int elem_size) temp_plan {
    size := length * elem_size
    stack_temp_plan("buf", size, true)
}

func temp_needs_clear(temp_plan plan) bool {
    plan.clear || plan.size > 1024
}

func temp_address_kind(temp_plan plan) string {
    if plan.stack_ok {
        return "stack"
    }
    "heap"
}
