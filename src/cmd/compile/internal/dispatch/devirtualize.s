package compile.internal.dispatch.devirtualize
import (
    "compile.internal.mir"
    "std.prelude"
)
func estimate_devirtualized_sites(string mir_text) int {
    candidates := count_token(mir_text, "dyn") + count_token(mir_text, "iface")
    if candidates <= 0 {
        return 0
    }
    candidates / 2
}

func estimate_devirtualized_sites_graph(mir_graph graph) int {
    candidates := 0
    i := 0
    for i < std.prelude.len(graph.blocks) {
        block := graph.blocks[i]
        j := 0
        for j < std.prelude.len(block.statements) {
            switch block.statements[j] {
                mir_statement::eval(eval_stmt) : {
                    if eval_stmt.op == "dynamic_call" || eval_stmt.op == "iface_call" || eval_stmt.op == "member_call" {
                        candidates = candidates + 1
                    }
                    if std.prelude.len(eval_stmt.args) > 0 {
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
    total := 0
    i := 0
    for i <= std.prelude.len(text) - std.prelude.len(token) {
        if std.prelude.slice(text, i, i + std.prelude.len(token)) == token {
            total = total + 1
            i = i + std.prelude.len(token)
        } else {
            i = i + 1
        }
    }
    total
}
