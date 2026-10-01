package inline

struct inline_cost {
    node_id: int
    cost: int
    benefit: int
    call_count: int
    is_leaf: int
    has_loops: int
}

struct inlining_context {
    func_id: int
    inline_threshold: int
    max_depth: int
    current_depth: int
    inlined_count: int
    total_saved_bytes: int
}

func inline_new_context(int func_id) inlining_context {
    ctx := inlining_context {
        func_id: func_id,
        inline_threshold: 80,
        max_depth: 5,
        current_depth: 0,
        inlined_count: 0,
        total_saved_bytes: 0
    }
    return ctx
}

func inline_compute_cost(int func_size, int call_count, int is_recursive) int {
    if func_size < 0 || func_size > 100000 {
        return 100000
    }

    int cost = func_size

    if call_count > 10 {
        cost = cost + (call_count * 5)
    }

    if is_recursive == 1 {
        cost = cost + 1000
    }

    return cost
}

func inline_compute_benefit(int call_count, int caller_frequency) int {
    if call_count <= 0 {
        return 0
    }

    int benefit = call_count * 10
    benefit = benefit + caller_frequency

    return benefit
}

func inline_should_inline(inlining_context* ctx, int func_size, int call_count) int {
    if ctx == 0 {
        return 0
    }

    if ctx.current_depth >= ctx.max_depth {
        return 0
    }

    if func_size <= 0 || func_size > 10000 {
        return 0
    }

    int cost = inline_compute_cost(func_size, call_count, 0)

    if cost > ctx.inline_threshold {
        return 0
    }

    if call_count < 1 {
        return 0
    }

    return 1
}

func inline_analyze_function(inlining_context* ctx, int func_id, int func_size) int {
    if ctx == 0 || func_id < 0 {
        return -1
    }

    if ctx.current_depth >= ctx.max_depth {
        return -1
    }

    ctx.current_depth = ctx.current_depth + 1

    int base_cost = func_size
    int benefit = inline_compute_benefit(1, 10)

    ctx.current_depth = ctx.current_depth - 1

    return base_cost
}

func inline_try_inline_call(inlining_context* ctx, int caller_id, int callee_id, int callee_size) int {
    if ctx == 0 || caller_id < 0 || callee_id < 0 {
        return -1
    }

    if inline_should_inline(ctx, callee_size, 1) == 0 {
        return 0
    }

    ctx.inlined_count = ctx.inlined_count + 1
    ctx.total_saved_bytes = ctx.total_saved_bytes + (callee_size / 2)

    return 1
}

func inline_collect_call_sites(inlining_context* ctx, int* call_nodes, int call_count) int {
    if ctx == 0 || call_nodes == 0 {
        return -1
    }

    int i = 0
    int processed = 0

    for i < call_count {
        if call_nodes[i] < 0 {
            break
        }

        processed = processed + 1
        i = i + 1
    }

    return processed
}

func inline_estimate_savings(inlining_context* ctx, int original_size, int inlined_size) int {
    if ctx == 0 || original_size <= 0 {
        return 0
    }

    int call_overhead = 8
    int saved = call_overhead + (original_size - inlined_size)

    if saved > 0 {
        return saved
    }

    return 0
}

func inline_can_inline_recursive(int func_id, int target_func_id, int depth) int {
    if func_id == target_func_id {
        return 0
    }

    if depth > 10 {
        return 0
    }

    return 1
}

func inline_apply_inlining(inlining_context* ctx, int caller_id, int callee_id) int {
    if ctx == 0 {
        return -1
    }

    if inline_can_inline_recursive(caller_id, callee_id, 0) == 0 {
        return -1
    }

    ctx.inlined_count = ctx.inlined_count + 1

    return callee_id
}

func inline_optimize_hot_path(inlining_context* ctx, int* hot_call_sites, int count) int {
    if ctx == 0 || hot_call_sites == 0 {
        return -1
    }

    int i = 0
    int inlined = 0

    for i < count {
        if hot_call_sites[i] < 0 {
            break
        }

        inlined = inlined + 1
        i = i + 1
    }

    ctx.inlined_count = ctx.inlined_count + inlined

    return inlined
}

func inline_get_inlined_count(inlining_context* ctx) int {
    if ctx == 0 {
        return 0
    }

    return ctx.inlined_count
}

func inline_get_total_savings(inlining_context* ctx) int {
    if ctx == 0 {
        return 0
    }

    return ctx.total_saved_bytes
}
