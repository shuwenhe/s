package compile.internal.base

func run_hashdebug_tests() int {
    var hd_y = new_hash_debug("gossahash", "y")
    if !match_pkg_func(hd_y, "anything", "anyfunc") {
        return 1
    }

    var hd_n = new_hash_debug("gossahash", "n")
    if match_pkg_func(hd_n, "anything", "anyfunc") {
        return 1
    }

    var hd_empty = new_hash_debug("gossahash", "")
    if !match_pkg_func(hd_empty, "pkg", "fn") {
        return 1
    }

    var hd_suffix = new_hash_debug("gossahash", "worker")
    if !match_pkg_func(hd_suffix, "demo", "worker") {
        return 1
    }
    if match_pkg_func(hd_suffix, "demo", "other") {
        return 1
    }

    var hd_ex = new_hash_debug("gossahash", "worker/-bad")
    if !match_pkg_func(hd_ex, "demo", "worker") {
        return 1
    }
    if match_pkg_func(hd_ex, "demo", "bad") {
        return 1
    }

    0
}
