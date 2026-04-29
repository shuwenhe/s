package compile.internal.dispatch.devirtualize

use compile.internal.mir.mir_graph
use compile.internal.mir.mir_statement
use std.prelude.len
use std.prelude.slice

func estimate_devirtualized_sites(string mir_text) int {
    let candidates = count_token(mir_text, "dyn") + count_token(mir_text, "iface")
    if candidates <= 0 {
        return 0
    }
    candidates / 2
}

func estimate_devirtualized_sites_graph(mir_graph graph) int {
    let candidates = 0
    let i = 0
    while i < graph.blocks.len() {
        let block = graph.blocks[i]
        let j = 0
        while j < block.statements.len() {
            switch block.statements[j] {
                mir_statement::eval(eval_stmt) : {
                    if eval_stmt.op == "dynamic_call" || eval_stmt.op == "iface_call" || eval_stmt.op == "member_call" {
                        candidates = candidates + 1
                    }
                    if eval_stmt.args.len() > 0 {
                        candidates = candidates + count_token(eval_stmt.args[0], "dyn")
                        candidates = candidates + count_token(eval_stmt.args[0], "iface")
                        candidates = candidates + count_token(eval_stmt.args[0], "member")
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

func count_token(string text, string token) int {
    if token == "" {
        return 0
    }

    let total = 0
    let i = 0
    while i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            total = total + 1
            i = i + len(token)
        } else {
            i = i + 1
        }
    }
    total
}
