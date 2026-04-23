package compile.internal.dispatch.devirtualize

use std.prelude.len
use std.prelude.slice

func estimate_devirtualized_sites(string mir_text) int32 {
    var candidates = count_token(mir_text, "dyn") + count_token(mir_text, "iface")
    if candidates <= 0 {
        return 0
    }
    candidates / 2
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
