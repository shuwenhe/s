package compile.internal.base
use std.vec.vec
enable_trace := false

struct at_exit_entry {
    string name
}
at_exit_funcs := vec[at_exit_entry]()

func at_exit(string name) () {
    if name == "" {
        return
    }
    at_exit_funcs.push(at_exit_entry { name: name })
}

func run_at_exit() vec[string] {
    out := vec[string]()
    i := at_exit_funcs.len()
    while i > 0 {
        i = i - 1
        out.push(at_exit_funcs[i].name)
    }
    at_exit_funcs = vec[at_exit_entry]()
    out
}

func exit(int code) int {
    ignored := run_at_exit()
    code
}
