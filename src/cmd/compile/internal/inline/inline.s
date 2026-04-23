package compile.internal.inline

use compile.internal.mir.mir_graph
use compile.internal.mir.mir_statement
use std.prelude.len
use std.prelude.slice

func estimate_inline_sites(string mir_text) int32 {
    var calls = count_token(mir_text, " call=")
    if calls <= 0 {
        return 0
    }

    calls / 2
}

func estimate_inline_sites_graph(mir_graph graph) int32 {
    var call_sites = 0
    var i = 0
    while i < graph.blocks.len() {
        var block = graph.blocks[i]
        var j = 0
        while j < block.statements.len() {
            switch block.statements[j] {
                mir_statement::eval(eval_stmt) : {
                    if eval_stmt.op == "call" {
                        call_sites = call_sites + 1
                    } else if eval_stmt.args.len() > 0 {
                        if count_token(eval_stmt.args[0], "call ") > 0 || count_token(eval_stmt.args[0], "(") > 0 {
                            call_sites = call_sites + 1
                        }
                    }
                }
                _ : (),
            }
            j = j + 1
        }
        i = i + 1
    }

    if call_sites <= 0 {
        return 0
    }
    call_sites / 2
}

func count_token(string text, string token) int32 {
    if token == "" {
        return 0
    }

    var total = 0
    var i = 0
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
