package compile.internal.gc

use std.vec.vec

func profile_name(string target, string suffix) string {
    if target == "" {
        return ""
    }
    if ends_with_slash(target) {
        return target + "compile" + suffix
    }
    target + suffix
}

func pick_pkgpath(vec[string] args) string {
    if args.len() > 2 {
        return args[2]
    }
    "main"
}

func clamp_backend_workers(int requested) int {
    if requested <= 0 {
        return 1
    }
    if requested > 64 {
        return 64
    }
    requested
}

func ends_with_slash(string text) bool {
    if text == "" {
        return false
    }
    let last = text[text.len() - 1]
    last == "/" || last == "\\"
}
