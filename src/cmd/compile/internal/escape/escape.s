package compile.internal.escape

use std.prelude.len
use std.prelude.slice

func estimate_escape_sites(string mir_text) int32 {
    count_token(mir_text, "alloc") + count_token(mir_text, "borrow")
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
