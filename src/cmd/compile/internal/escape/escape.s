package compile.internal.escape

import (
    "compile.internal.mir"
    "std.prelude"
)

func new_escape_analysis() escape_analysis {
    escape_analysis {
        graph: new_escape_graph(),
        leaks: new_leak_summary(),
    }
}

func (a* escape_analysis) analyze_variable(int variable_id, bool is_pointer, bool address_taken, bool returned, bool stored_global) int {
    escape_analysis_analyze_variable(a, variable_id, is_pointer, address_taken, returned, stored_global)
}

func escape_analysis_analyze_variable(escape_analysis a, int variable_id, bool is_pointer, bool address_taken, bool returned, bool stored_global) int {
    level := classify_escape(is_pointer, address_taken, returned, stored_global, false)
    info := escape_info {
        variable_id: variable_id,
        level: level,
        is_pointer: is_pointer,
        address_taken: address_taken,
        returned: returned,
        stored_global: stored_global,
        stored_heap: false,
        reason: escape_reason(level),
    }
    return level
}

func classify_escape(bool is_pointer, bool address_taken, bool returned, bool stored_global, bool stored_heap) int {
    if stored_heap {
        return escape_heap
    }
    if stored_global {
        return escape_global
    }
    if returned {
        return escape_func
    }
    if is_pointer && address_taken {
        return escape_func
    }
    escape_none
}

func escape_reason(int level) string {
    "escape classification"
}

func estimate_escape_sites(string mir_text) int {
    candidates := escape_count_token(mir_text, "borrow") + escape_count_token(mir_text, "&") + escape_count_token(mir_text, "store") + escape_count_token(mir_text, "return")
    if candidates <= 0 {
        return 0
    }
    candidates / 2
}

func estimate_escape_sites_graph(mir_graph graph) int {
    text := compile.internal.mir.dump_graph(graph)
    score := estimate_escape_sites(text)
    if score > 0 {
        return score
    }
    candidates := 0
    i := 0
    for i < std.prelude.len(graph.blocks) {
        block := graph.blocks[i]
        j := 0
        for j < std.prelude.len(block.statements) {
            switch block.statements[j] {
                mir_statement::assign(assign_stmt) : {
                    candidates = candidates + classify_assign_escape_op(assign_stmt.op)
                    candidates = candidates + std.prelude.len(assign_stmt.args) / 4
                }
                mir_statement::eval(eval_stmt) : {
                    candidates = candidates + classify_expr_escape_op(eval_stmt.op)
                    if std.prelude.len(eval_stmt.args) > 0 {
                        candidates = candidates + escape_count_token(eval_stmt.args[0], "&")
                        candidates = candidates + escape_count_token(eval_stmt.args[0], "borrow")
                    }
                }
                _ : (),
            }
            j = j + 1
        }
        i = i + 1
    }
    if candidates <= 0 {
        return 0
    }
    candidates / 2
}
