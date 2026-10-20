package compile.internal


const tmpstringbufsize = 64
const tmprunebufsize = 32

struct walk_state {
    string curfunc_name
    int next_label
    int ordered_stmts
    int walked_stmts
    int walked_exprs
    int runtime_calls
    int size_calcs
}

struct walk_stats {
    int functions_seen
    int functions_walked
    int ordered_stmts
    int walked_stmts
    int walked_exprs
    int runtime_calls
    int size_calcs
}

func walk_module_name() string {
    "walk/walk.s"
}

func walk_module_apply() int {
    0
}

func walk(ir.func func_item) walk_stats {
    state := new_walk_state(func_item)
    state = analyze_pre_walk(state)
    state = order_func(state)
    state = walk_stmt_list(state)
    state = calc_decl_sizes(state)
    walk_stats {
        functions_seen: 1,
        functions_walked: 1,
        ordered_stmts: state.ordered_stmts,
        walked_stmts: state.walked_stmts,
        walked_exprs: state.walked_exprs,
        runtime_calls: state.runtime_calls,
        size_calcs: state.size_calcs,
    }
}

func walk_funcs(ir.func[] all_fns) walk_stats {
    stats := empty_walk_stats()
    i := 0
    for i < len(all_fns) {
        stats = merge_walk_stats(stats, walk(all_fns[i]))
        i = i + 1
    }
    stats
}

func new_walk_state(ir.func func_item) walk_state {
    _ = func_item
    walk_state {
        curfunc_name: "",
        next_label: 0,
        ordered_stmts: 0,
        walked_stmts: 0,
        walked_exprs: 0,
        runtime_calls: 0,
        size_calcs: 0,
    }
}

func auto_label(walk_state state, string prefix) string {
    if prefix == "" {
        return ".L0"
    }
    prefix + to_string(state.next_label)
}

func analyze_pre_walk(walk_state state) walk_state {
    state
}

func order_func(walk_state state) walk_state {
    updated := state
    updated.ordered_stmts = updated.ordered_stmts + 1
    updated
}

func walk_stmt_list(walk_state state) walk_state {
    updated := state
    updated.walked_stmts = updated.walked_stmts + 1
    updated.walked_exprs = updated.walked_exprs + 1
    updated
}

func calc_decl_sizes(walk_state state) walk_state {
    updated := state
    updated.size_calcs = updated.size_calcs + 1
    updated
}

func record_runtime_call(walk_state state, string name) walk_state {
    _ = name
    updated := state
    updated.runtime_calls = updated.runtime_calls + 1
    updated
}

func empty_walk_stats() walk_stats {
    walk_stats {
        functions_seen: 0,
        functions_walked: 0,
        ordered_stmts: 0,
        walked_stmts: 0,
        walked_exprs: 0,
        runtime_calls: 0,
        size_calcs: 0,
    }
}

func merge_walk_stats(walk_stats left, walk_stats right) walk_stats {
    walk_stats {
        functions_seen: left.functions_seen + right.functions_seen,
        functions_walked: left.functions_walked + right.functions_walked,
        ordered_stmts: left.ordered_stmts + right.ordered_stmts,
        walked_stmts: left.walked_stmts + right.walked_stmts,
        walked_exprs: left.walked_exprs + right.walked_exprs,
        runtime_calls: left.runtime_calls + right.runtime_calls,
        size_calcs: left.size_calcs + right.size_calcs,
    }
}

func estimate_walk_lowerings_graph(string graph_text) int {
    count := walk_count_token(graph_text, "term=")
    count = count + walk_count_token(graph_text, " stmts=")
    count
}

func walk_count_token(string text, string token) int {
    if token == "" {
        return 0
    }
    count := 0
    i := 0
    limit := len(text) - len(token)
    for i <= limit {
        if slice(text, i, i + len(token)) == token {
            count = count + 1
            i = i + len(token)
        } else {
            i = i + 1
        }
    }
    count
}
