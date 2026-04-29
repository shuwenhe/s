package compile.internal.base

use std.vec.vec

struct error_msg {
    string pos
    string msg
    int code
    bool warning
}

let pos = ""
let error_msgs = vec[error_msg]()
let num_errors = 0
let num_syntax_errors = 0

func errors() int {
    num_errors
}

func syntax_errors() int {
    num_syntax_errors
}

func add_error_msg(string at, int code, string message, bool warning) () {
    let full = message
    if at != "" {
        full = at + ": " + message
    }
    error_msgs.push(error_msg {
        pos: at,
        msg: full,
        code: code,
        warning: warning,
    })
}

func flush_errors() string {
    let out = ""
    let i = 0
    while i < error_msgs.len() {
        out = out + error_msgs[i].msg + "\n"
        i = i + 1
    }
    error_msgs = vec[error_msg]()
    out
}

func errorf(string message) () {
    errorf_at(pos, 0, message)
}

func errorf_at(string at, int code, string message) () {
    if starts_with_text(message, "syntax error") {
        num_syntax_errors = num_syntax_errors + 1
    }
    add_error_msg(at, code, message, false)
    num_errors = num_errors + 1
}

func warnf_at(string at, string message) () {
    add_error_msg(at, 0, message, true)
}

func fatalf(string message) string {
    fatalf_at(pos, message)
}

func fatalf_at(string at, string message) string {
    add_error_msg(at, 0, "internal compiler error: " + message, false)
    flush_errors()
}

func assert(bool ok) () {
    if !ok {
        let ignored = fatalf("assertion failed")
    }
}

func assertf(bool ok, string message) () {
    if !ok {
        let ignored = fatalf(message)
    }
}

func starts_with_text(string text, string prefix) bool {
    if len(text) < len(prefix) {
        return false
    }
    return slice(text, 0, len(prefix)) == prefix
}
