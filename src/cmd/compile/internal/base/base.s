package compile.internal.base

use std.vec.vec

var enable_trace = false

struct at_exit_entry {
    string name
}

var at_exit_funcs = vec[at_exit_entry]()

func at_exit(string name) () {
    if name == "" {
        return
    }
    at_exit_funcs.push(at_exit_entry { name: name })
}

func run_at_exit() vec[string] {
    var out = vec[string]()
    var i = at_exit_funcs.len()
    while i > 0 {
        i = i - 1
        out.push(at_exit_funcs[i].name)
    }
    at_exit_funcs = vec[at_exit_entry]()
    out
}

func exit(int code) int {
    var ignored = run_at_exit()
    code
}
