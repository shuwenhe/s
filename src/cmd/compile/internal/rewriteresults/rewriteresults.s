package compile.internal


struct rewrite_candidate {
    string local_name
    string result_name
    string type_name
    bool anonymous_result
    bool bare_decl
    bool heap_escape
    bool captured
    bool conflict
}

struct rewrite_stats {
    int functions_seen
    int functions_rewritten
    int candidates_seen
    int candidates_rewritten
    int skipped_defer
    int skipped_conflict
    int skipped_capture
    int skipped_heap
}

func rewrite_result_funcs(ir.func[] fns) rewrite_stats {
    stats := rewrite_stats {
        functions_seen: 0,
        functions_rewritten: 0,
        candidates_seen: 0,
        candidates_rewritten: 0,
        skipped_defer: 0,
        skipped_conflict: 0,
        skipped_capture: 0,
        skipped_heap: 0,
    }
    i := 0
    for i < len(fns) {
        func_item := fns[i]
        stats.functions_seen = stats.functions_seen + 1
        stats = merge_rewrite_stats(stats, rewrite(func_item))
        i = i + 1
    }
    stats
}

func rewrite(ir.func func_item) rewrite_stats {
    _ = func_item
    rewrite_stats {
        functions_seen: 0,
        functions_rewritten: 0,
        candidates_seen: 0,
        candidates_rewritten: 0,
        skipped_defer: 0,
        skipped_conflict: 0,
        skipped_capture: 0,
        skipped_heap: 0,
    }
}

func is_candidate_local(rewrite_candidate candidate) bool {
    candidate.anonymous_result
        && candidate.bare_decl
        && !candidate.heap_escape
        && !candidate.captured
        && !candidate.conflict
        && candidate.local_name != ""
        && candidate.result_name != ""
        && candidate.type_name != ""
}

func apply_candidate(rewrite_candidate candidate) rewrite_stats {
    stats := rewrite_stats {
        functions_seen: 0,
        functions_rewritten: 0,
        candidates_seen: 1,
        candidates_rewritten: 0,
        skipped_defer: 0,
        skipped_conflict: 0,
        skipped_capture: 0,
        skipped_heap: 0,
    }
    if candidate.conflict {
        stats.skipped_conflict = 1
        return stats
    }
    if candidate.captured {
        stats.skipped_capture = 1
        return stats
    }
    if candidate.heap_escape {
        stats.skipped_heap = 1
        return stats
    }
    if is_candidate_local(candidate) {
        stats.functions_rewritten = 1
        stats.candidates_rewritten = 1
    }
    stats
}

func merge_rewrite_stats(rewrite_stats left, rewrite_stats right) rewrite_stats {
    rewrite_stats {
        functions_seen: left.functions_seen + right.functions_seen,
        functions_rewritten: left.functions_rewritten + right.functions_rewritten,
        candidates_seen: left.candidates_seen + right.candidates_seen,
        candidates_rewritten: left.candidates_rewritten + right.candidates_rewritten,
        skipped_defer: left.skipped_defer + right.skipped_defer,
        skipped_conflict: left.skipped_conflict + right.skipped_conflict,
        skipped_capture: left.skipped_capture + right.skipped_capture,
        skipped_heap: left.skipped_heap + right.skipped_heap,
    }
}

func estimate_rewrite_results_graph(string graph_text) int {
    _ = graph_text
    0
}
