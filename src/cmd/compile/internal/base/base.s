package compile.internal.base

use std.vec.vec

let enable_trace = false

struct at_exit_entry {
    string name
}

let at_exit_funcs = vec[at_exit_entry]()

func at_exit(string name) () {
    if name == "" {
        return
    }
    at_exit_funcs.push(at_exit_entry { name: name })
}

func run_at_exit() vec[string] {
    let out = vec[string]()
    let i = at_exit_funcs.len()
    while i > 0 {
        i = i - 1
        out.push(at_exit_funcs[i].name)
    }
    at_exit_funcs = vec[at_exit_entry]()
    out
}

func exit(int code) int {
    let ignored = run_at_exit()
    code
}
