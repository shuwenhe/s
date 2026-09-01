package compile.internal.escape
use compile.internal.mir.mir_graph
use compile.internal.mir.mir_statement
use std.prelude.len
use std.prelude.slice
func estimate_escape_sites(string mir_text) int {
    count_token(mir_text, "alloc") + count_token(mir_text, "borrow")
}

func estimate_escape_sites_graph(mir_graph graph) int {
    total := 0
    i := 0
    for i < len(graph.blocks) {
        block := graph.blocks[i]
        j := 0
        for j < len(block.statements) {
            switch block.statements[j] {
                mir_statement::eval(eval_stmt) : {
                    if eval_stmt.op == "alloc" || eval_stmt.op == "borrow" || eval_stmt.op == "address_of" {
                        total = total + 1
                    }
                    if len(eval_stmt.args) > 0 {
                        total = total + count_token(eval_stmt.args[0], "alloc")
                        total = total + count_token(eval_stmt.args[0], "borrow")
                        total = total + count_token(eval_stmt.args[0], "&")
                    }
                }
                _ : (),
            }
            j = j + 1
        }
        i = i + 1
    }
    total
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
