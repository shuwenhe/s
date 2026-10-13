package compile.internal.slice

import (
    "compile.internal.ir"
)

struct slice_info {
    string name
    string elem_type
    int ok_uses
    int all_uses
    int append_weight
    int decl_depth
    bool cap_used
    bool has_transition
    bool disabled
}

struct slice_stats {
    int functions_seen
    int functions_analyzed
    int candidates_seen
    int candidates_rewritten
    int appends_seen
    int transitions_seen
    int disabled_unknown_use
    int disabled_loop_transition
}

func slice_unit_name() string {
    "slice/slice.s"
}

func slice_unit_ready() int {
    1
}

func funcs(ir.func[] all_fns) slice_stats {
    stats := slice_stats {
        functions_seen: 0,
        functions_analyzed: 0,
        candidates_seen: 0,
        candidates_rewritten: 0,
        appends_seen: 0,
        transitions_seen: 0,
        disabled_unknown_use: 0,
        disabled_loop_transition: 0,
    }
    i := 0
    for i < len(all_fns) {
        stats.functions_seen = stats.functions_seen + 1
        stats = merge_slice_stats(stats, analyze(all_fns[i]))
        i = i + 1
    }
    stats
}

func analyze(ir.func func_item) slice_stats {
    _ = func_item
    slice_stats {
        functions_seen: 0,
        functions_analyzed: 0,
        candidates_seen: 0,
        candidates_rewritten: 0,
        appends_seen: 0,
        transitions_seen: 0,
        disabled_unknown_use: 0,
        disabled_loop_transition: 0,
    }
}

func new_slice_info(string name, string elem_type, int decl_depth) slice_info {
    slice_info {
        name: name,
        elem_type: elem_type,
        ok_uses: 0,
        all_uses: 0,
        append_weight: 0,
        decl_depth: decl_depth,
        cap_used: false,
        has_transition: false,
        disabled: false,
    }
}

func record_slice_use(slice_info info, bool understood) slice_info {
    updated := info
    updated.all_uses = updated.all_uses + 1
    if understood {
        updated.ok_uses = updated.ok_uses + 1
    }
    updated
}

func record_slice_append(slice_info info, int loop_depth) slice_info {
    updated := record_slice_use(info, true)
    updated = record_slice_use(updated, true)
    extra := loop_depth - updated.decl_depth
    if extra < 0 {
        extra = 0
    }
    updated.append_weight = updated.append_weight + 1 + extra
    updated
}

func record_slice_transition(slice_info info, int loop_depth) slice_info {
    updated := record_slice_use(info, true)
    if updated.has_transition {
        updated.disabled = true
        return updated
    }
    if loop_depth > updated.decl_depth {
        updated.disabled = true
        return updated
    }
    updated.has_transition = true
    updated
}

func slice_can_rewrite(slice_info info) bool {
    !info.disabled
        && info.name != ""
        && info.elem_type != ""
        && info.ok_uses == info.all_uses
        && info.has_transition
        && info.append_weight >= 2
}

func apply_slice_candidate(slice_info info) slice_stats {
    stats := slice_stats {
        functions_seen: 0,
        functions_analyzed: 1,
        candidates_seen: 1,
        candidates_rewritten: 0,
        appends_seen: info.append_weight,
        transitions_seen: 0,
        disabled_unknown_use: 0,
        disabled_loop_transition: 0,
    }
    if info.has_transition {
        stats.transitions_seen = 1
    }
    if info.disabled {
        stats.disabled_unknown_use = 1
        return stats
    }
    if slice_can_rewrite(info) {
        stats.candidates_rewritten = 1
    }
    stats
}

func merge_slice_stats(slice_stats left, slice_stats right) slice_stats {
    slice_stats {
        functions_seen: left.functions_seen + right.functions_seen,
        functions_analyzed: left.functions_analyzed + right.functions_analyzed,
        candidates_seen: left.candidates_seen + right.candidates_seen,
        candidates_rewritten: left.candidates_rewritten + right.candidates_rewritten,
        appends_seen: left.appends_seen + right.appends_seen,
        transitions_seen: left.transitions_seen + right.transitions_seen,
        disabled_unknown_use: left.disabled_unknown_use + right.disabled_unknown_use,
        disabled_loop_transition: left.disabled_loop_transition + right.disabled_loop_transition,
    }
}

func estimate_slice_stack_moves_graph(string graph_text) int {
    appends := count_token(graph_text, "append(")
    returns := count_token(graph_text, "return")
    if appends < 2 {
        return 0
    }
    if returns == 0 {
        return 0
    }
    if appends < returns {
        return appends
    }
    returns
}

func count_token(string text, string token) int {
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
