package cmd

import (
    "std"
)

func profile_name(string target, string suffix) string {
    target + "_" + suffix
}

func pick_pkgpath(string[] args) string {
    if len(args) > 0 {
        return args[0]
    }
    "main"
}

func clamp_backend_workers(int requested) int {
    if requested <= 0 {
        return 1
    }
    if requested > 128 {
        return 128
    }
    requested
}

func ends_with_slash(string text) bool {
    if len(text) == 0 {
        return false
    }
    text[len(text) - 1] == '/'
}
