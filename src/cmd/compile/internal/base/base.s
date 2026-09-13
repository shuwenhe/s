package compile.internal.base
use std.slices
enable_trace := false
struct at_exit_entry {
    string name
}
at_exit_funcs := at_exit_entry[]()

func at_exit(string name) () {
    if name == "" {
        return
    }
    at_exit_funcs = append(at_exit_funcs, at_exit_entry { name: name })
}

func run_at_exit() string[] {
    out := string[]()
    i := len(at_exit_funcs)
    for i > 0 {
        i = i - 1
        out = append(out, at_exit_funcs[i].name)
    }
    at_exit_funcs = at_exit_entry[]()
    out
}

func exit(int code) int {
    ignored := run_at_exit()
    code
}
