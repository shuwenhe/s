package compile.internal.inline

use std.prelude.len
use std.prelude.slice

func estimate_inline_sites(string mir_text) int32 {
    var calls = count_token(mir_text, " call=")
    if calls <= 0 {
        return 0
    }

    calls / 2
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
