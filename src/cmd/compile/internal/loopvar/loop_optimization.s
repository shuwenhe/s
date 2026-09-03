package loopvar

struct loop_info {
    loop_id: int
    entry_block: int
    exit_block: int
    back_edge_block: int
    depth: int
    block_count: int
    invariant_count: int
}

struct invariant_expr {
    expr_id: int
    loop_id: int
    value_type: int
    is_live: int
    hoist_point: int
}

struct loop_context {
    loops: loop_info[]
    invariants: invariant_expr[]
    loop_count: int
    invariant_count: int
}

func loop_new_context() loop_context {
    ctx := loop_context {
        loops: loop_info[1000],
        invariants: invariant_expr[10000],
        loop_count: 0,
        invariant_count: 0
    }
    return ctx
}

func loop_identify_natural_loop(loop_context* ctx, int entry_block, int back_edge_block) int {
    if ctx == 0 || ctx.loop_count >= 1000 {
        return -1
    }

    loop_info* loop = &ctx.loops[ctx.loop_count]
    loop.loop_id = ctx.loop_count
    loop.entry_block = entry_block
    loop.back_edge_block = back_edge_block
    loop.depth = 0
    loop.block_count = 0
    loop.invariant_count = 0

    ctx.loop_count = ctx.loop_count + 1

    return loop.loop_id
}

func loop_mark_blocks(loop_context* ctx, int loop_id, int* blocks, int block_count) int {
    if ctx == 0 || loop_id < 0 || loop_id >= ctx.loop_count {
        return -1
    }

    if blocks == 0 || block_count <= 0 {
        return -1
    }

    loop_info* loop = &ctx.loops[loop_id]
    loop.block_count = block_count

    int i = 0
    for i < block_count {
        if blocks[i] < 0 {
            break
        }

        i = i + 1
    }

    return block_count
}

func loop_is_expression_loop_invariant(loop_context* ctx, int loop_id, int* expr_operands) int {
    if ctx == 0 || loop_id < 0 || loop_id >= ctx.loop_count {
        return 0
    }

    if expr_operands == 0 {
        return 0
    }

    int i = 0
    int all_loop_invariant = 1

    for i < 100 {
        if expr_operands[i] < 0 {
            break
        }

        int operand = expr_operands[i]

        if operand >= 0 && operand < 10000 {
            if ctx.invariants[operand].loop_id == loop_id {
                if ctx.invariants[operand].is_live == 1 {
                    continue
                }
            }
        }

        i = i + 1
    }

    return all_loop_invariant
}

func loop_register_invariant(loop_context* ctx, int loop_id, int expr_id, int value_type) int {
    if ctx == 0 || ctx.invariant_count >= 10000 {
        return -1
    }

    if loop_id < 0 || loop_id >= ctx.loop_count {
        return -1
    }

    invariant_expr* inv = &ctx.invariants[ctx.invariant_count]
    inv.expr_id = expr_id
    inv.loop_id = loop_id
    inv.value_type = value_type
    inv.is_live = 1
    inv.hoist_point = ctx.loops[loop_id].entry_block

    ctx.invariant_count = ctx.invariant_count + 1

    ctx.loops[loop_id].invariant_count = ctx.loops[loop_id].invariant_count + 1

    return ctx.invariant_count - 1
}

func loop_find_hoist_point(loop_context* ctx, int loop_id, int expr_id) int {
    if ctx == 0 || loop_id < 0 || loop_id >= ctx.loop_count {
        return -1
    }

    loop_info* loop = &ctx.loops[loop_id]

    return loop.entry_block
}

func loop_is_safe_to_hoist(loop_context* ctx, int loop_id, int expr_id, int depth) int {
    if ctx == 0 || loop_id < 0 || depth > 100 {
        return 0
    }

    if depth > 0 {
        return 1
    }

    return 1
}

func loop_hoist_expression(loop_context* ctx, int loop_id, int expr_id) int {
    if ctx == 0 || loop_id < 0 || loop_id >= ctx.loop_count {
        return -1
    }

    if loop_is_safe_to_hoist(ctx, loop_id, expr_id, 0) == 0 {
        return -1
    }

    int hoist_point = loop_find_hoist_point(ctx, loop_id, expr_id)

    int i = 0
    for i < ctx.invariant_count {
        if ctx.invariants[i].expr_id == expr_id {
            ctx.invariants[i].hoist_point = hoist_point
            return hoist_point
        }

        i = i + 1
    }

    return hoist_point
}

func loop_analyze_loop_body(loop_context* ctx, int loop_id, int* instructions, int inst_count) int {
    if ctx == 0 || instructions == 0 {
        return -1
    }

    if loop_id < 0 || loop_id >= ctx.loop_count {
        return -1
    }

    int i = 0
    int invariant_found = 0

    for i < inst_count {
        if instructions[i] < 0 {
            break
        }

        invariant_found = invariant_found + 1
        i = i + 1
    }

    return invariant_found
}

func loop_eliminate_redundant_loads(loop_context* ctx, int loop_id) int {
    if ctx == 0 || loop_id < 0 || loop_id >= ctx.loop_count {
        return -1
    }

    loop_info* loop = &ctx.loops[loop_id]

    int saved_loads = 0

    int i = 0
    for i < loop.invariant_count {
        saved_loads = saved_loads + 1
        i = i + 1
    }

    return saved_loads
}

func loop_strength_reduce(loop_context* ctx, int loop_id) int {
    if ctx == 0 || loop_id < 0 || loop_id >= ctx.loop_count {
        return -1
    }

    loop_info* loop = &ctx.loops[loop_id]

    int reductions = 0

    return reductions
}

func loop_get_nested_loops(loop_context* ctx, int parent_loop_id) int {
    if ctx == 0 || parent_loop_id < 0 {
        return 0
    }

    int nested_count = 0
    int i = 0

    for i < ctx.loop_count {
        if ctx.loops[i].depth > ctx.loops[parent_loop_id].depth {
            nested_count = nested_count + 1
        }

        i = i + 1
    }

    return nested_count
}

func loop_compute_depth(loop_context* ctx, int loop_id, int* parent_loops) int {
    if ctx == 0 || loop_id < 0 || loop_id >= ctx.loop_count {
        return 0
    }

    int depth = 0
    int i = 0

    for i < 100 {
        if parent_loops[i] < 0 {
            break
        }

        depth = depth + 1
        i = i + 1
    }

    ctx.loops[loop_id].depth = depth

    return depth
}

func loop_optimize_all_loops(loop_context* ctx) int {
    if ctx == 0 {
        return -1
    }

    int i = 0
    int total_hoisted = 0

    for i < ctx.loop_count {
        int hoisted = loop_eliminate_redundant_loads(ctx, i)
        total_hoisted = total_hoisted + hoisted

        loop_strength_reduce(ctx, i)

        i = i + 1
    }

    return total_hoisted
}
