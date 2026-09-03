package compile.internal.inline
use compile.internal.mir.mir_graph
use compile.internal.mir.dump_graph
use std.prelude.slice
func estimate_inline_sites(string mir_text) int {
    calls := count_token(mir_text, " call=")
    if calls <= 0 {
        return 0
    }
    calls / 2
}

func estimate_inline_sites_graph(mir_graph graph) int {
    call_sites := count_token(dump_graph(graph), "call")
    if call_sites <= 0 {
        return 0
    }
    call_sites / 2
}

func count_token(string text, string token) int {
    if token == "" {
        return 0
    }
    total := 0
    i := 0
    for i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            total = total + 1
            i = i + len(token)
        } else {
            i = i + 1
        }
    }
    total
}

struct inline_result {
    mir_graph graph
    int inlined_count
}

func can_inline_leaf(mir_graph callee) bool {
    if len(callee.blocks) != 1 || len(callee.blocks[0].statements) > 8 {
        return false
    }
    if callee.blocks[0].terminator.kind != "return" {
        return false
    }
    true
}

func inline_leaf_calls(mir_graph caller, mir_graph callee) inline_result {
    result := inline_result { graph: caller, inlined_count: 0 }
    if !can_inline_leaf(callee) || caller.function_name == callee.function_name {
        return result
    }
    block_index := 0
    for block_index < len(result.graph.blocks) {
        block := result.graph.blocks[block_index]
        rewritten := mir_statement[] {}
        statement_index := 0
        has_call := count_token(dump_graph(caller), callee.function_name) > 0
        for statement_index < len(block.statements) {
            rewritten = append(rewritten, block.statements[statement_index])
            statement_index = statement_index + 1
        }
        if has_call && block_index == caller.entry {
            callee_statement_index := 0
            for callee_statement_index < len(callee.blocks[0].statements) {
                rewritten = append(rewritten, callee.blocks[0].statements[callee_statement_index])
                callee_statement_index = callee_statement_index + 1
            }
            result.inlined_count = 1
        }
        block.statements = rewritten
        block_index = block_index + 1
    }
    result
}
