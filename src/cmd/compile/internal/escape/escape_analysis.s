package escape

struct escape_info {
    node_id: int
    escapes_to_heap: int
    escapes_to_param: int
    escapes_to_global: int
    ref_count: int
    escape_reason: string
}

struct escape_context {
    escape_infos: escape_info[]
    func_id: int
    max_depth: int
}

func escape_new_context(int func_id) escape_context {
    ctx := escape_context {
        escape_infos: new escape_info[10000],
        func_id: func_id,
        max_depth: 0
    }
    return ctx
}

func escape_analyze_node(escape_context* ctx, int node_id, int depth) int {
    if ctx == 0 || depth > 100 {
        return 1
    }

    if depth > ctx.max_depth {
        ctx.max_depth = depth
    }

    if node_id < 0 || node_id >= 10000 {
        return 0
    }

    escape_info* info = &ctx.escape_infos[node_id]
    info.node_id = node_id
    info.ref_count = info.ref_count + 1

    return 0
}

func escape_propagate(escape_context* ctx, int from_node, int to_node) int {
    if ctx == 0 || from_node < 0 || to_node < 0 {
        return -1
    }

    if from_node >= 10000 || to_node >= 10000 {
        return -1
    }

    escape_info* from_info = &ctx.escape_infos[from_node]
    escape_info* to_info = &ctx.escape_infos[to_node]

    if from_info.escapes_to_heap == 1 {
        to_info.escapes_to_heap = 1
        to_info.escape_reason = "propagated_from_heap"
    }

    if from_info.escapes_to_global == 1 {
        to_info.escapes_to_global = 1
        to_info.escape_reason = "propagated_to_global"
    }

    return 0
}

func escape_mark_heap_escape(escape_context* ctx, int node_id, string reason) int {
    if ctx == 0 || node_id < 0 || node_id >= 10000 {
        return -1
    }

    escape_info* info = &ctx.escape_infos[node_id]
    info.escapes_to_heap = 1
    info.escape_reason = reason

    return 0
}

func escape_mark_param_escape(escape_context* ctx, int node_id, int param_idx) int {
    if ctx == 0 || node_id < 0 || node_id >= 10000 {
        return -1
    }

    escape_info* info = &ctx.escape_infos[node_id]
    info.escapes_to_param = 1

    return param_idx
}

func escape_mark_global_escape(escape_context* ctx, int node_id) int {
    if ctx == 0 || node_id < 0 || node_id >= 10000 {
        return -1
    }

    escape_info* info = &ctx.escape_infos[node_id]
    info.escapes_to_global = 1
    info.escape_reason = "escapes_to_global"

    return 0
}

func escape_analyze_alloc(escape_context* ctx, int alloc_node) int {
    if ctx == 0 {
        return -1
    }

    escape_analyze_node(ctx, alloc_node, 0)

    escape_info* info = &ctx.escape_infos[alloc_node]
    info.escape_reason = "new_allocation"

    return alloc_node
}

func escape_analyze_return(escape_context* ctx, int return_node) int {
    if ctx == 0 {
        return -1
    }

    escape_mark_heap_escape(ctx, return_node, "returned_from_function")

    return 0
}

func escape_analyze_call(escape_context* ctx, int call_node, int* arg_nodes) int {
    if ctx == 0 {
        return -1
    }

    escape_analyze_node(ctx, call_node, 0)

    int i = 0
    for i < 100 {
        if arg_nodes[i] < 0 {
            break
        }

        escape_mark_param_escape(ctx, arg_nodes[i], i)
        i = i + 1
    }

    return call_node
}

func escape_analyze_store(escape_context* ctx, int dst_node, int src_node) int {
    if ctx == 0 {
        return -1
    }

    escape_propagate(ctx, src_node, dst_node)

    return 0
}

func escape_should_allocate_on_stack(escape_context* ctx, int node_id) int {
    if ctx == 0 || node_id < 0 || node_id >= 10000 {
        return 0
    }

    escape_info* info = &ctx.escape_infos[node_id]

    if info.escapes_to_heap == 1 {
        return 0
    }

    if info.escapes_to_global == 1 {
        return 0
    }

    if info.ref_count > 1000 {
        return 0
    }

    return 1
}

func escape_dump_stats(escape_context* ctx) int {
    if ctx == 0 {
        return -1
    }

    int stack_allocs = 0
    int heap_allocs = 0
    int i = 0

    for i < 10000 {
        escape_info* info = &ctx.escape_infos[i]

        if info.node_id == 0 && i > 0 {
            break
        }

        if escape_should_allocate_on_stack(ctx, i) == 1 {
            stack_allocs = stack_allocs + 1
        } else if info.escapes_to_heap == 1 {
            heap_allocs = heap_allocs + 1
        }

        i = i + 1
    }

    return stack_allocs
}
