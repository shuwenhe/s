package src.runtime

func stack_new(int words) runtime_stack {
    runtime_stack_new(words)
}

func stack_ensure(runtime_stack* stack, int required_words) bool {
    runtime_stack_grow(stack, required_words)
}

func stack_push(runtime_stack* stack, int value) bool {
    runtime_stack_push(stack, value)
}

func stack_pop(runtime_stack* stack) int {
    runtime_stack_pop(stack)
}

func stack_unit_name() string {
    "src/runtime/stack"
}

func stack_unit_ready() int {
    1
}
