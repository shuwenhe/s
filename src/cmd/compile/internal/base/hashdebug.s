package compile.internal.base

use std.vec.vec

struct hash_mask {
    string name
    string suffix
    bool exclude
}

struct hash_debug {
    string name
    string raw
    bool file_suffix_only
    bool inline_suffix_only
    vec[hash_mask] matches
}

let hash_debug_default = new_hash_debug("gossahash", "")
let convert_hash = new_hash_debug("converthash", "")
let fma_hash = new_hash_debug("fmahash", "")
let loop_var_hash = new_hash_debug("loopvarhash", "")
let pgo_hash = new_hash_debug("pgohash", "")
let literal_alloc_hash = new_hash_debug("literalallochash", "")
let merge_locals_hash = new_hash_debug("mergelocalshash", "")
let variable_make_hash = new_hash_debug("variablemakehash", "")

func has_debug_hash() bool {
    hash_debug_default.raw != ""
}

func new_hash_debug(string name, string raw) hash_debug {
    let out = hash_debug {
        name: name,
        raw: raw,
        file_suffix_only: false,
        inline_suffix_only: false,
        matches: vec[hash_mask](),
    }
    if raw == "" {
        return out
    }
    if raw == "y" || raw == "Y" {
        out.matches.push(hash_mask { name: name, suffix: "", exclude: false })
        return out
    }
    if raw == "n" || raw == "N" {
        out.matches.push(hash_mask { name: name, suffix: "*deny*", exclude: true })
        return out
    }

    let parts = split(raw, "/")
    let i = 0
    while i < parts.len() {
        let p = trim_spaces(parts[i])
        if p != "" {
            if starts_with(p, "-") {
                out.matches.push(hash_mask {
                    name: "exclude" + to_string(i),
                    suffix: slice(p, 1, len(p)),
                    exclude: true,
                })
            } else {
                out.matches.push(hash_mask {
                    name: name + to_string(i),
                    suffix: p,
                    exclude: false,
                })
            }
        }
        i = i + 1
    }
    out
}

func set_inline_suffix_only(hash_debug mut hd, bool on) hash_debug {
    hd.inline_suffix_only = on
    hd
}

func debug_hash_match_pkg_func(string pkg, string fn_name) bool {
    match_pkg_func(hash_debug_default, pkg, fn_name)
}

func match_pkg_func(hash_debug hd, string pkg, string fn_name) bool {
    if hd.raw == "" {
        return true
    }
    if hd.raw == "y" || hd.raw == "Y" {
        return true
    }
    if hd.raw == "n" || hd.raw == "N" {
        return false
    }

    let target = pkg + "." + fn_name
    let included = false
    let i = 0
    while i < hd.matches.len() {
        let m = hd.matches[i]
        if m.exclude {
            if m.suffix != "" && ends_with(target, m.suffix) {
                return false
            }
        } else if m.suffix == "" || ends_with(target, m.suffix) {
            included = true
        }
        i = i + 1
    }
    included
}

func split(string text, string sep) vec[string] {
    let out = vec[string]()
    if sep == "" {
        out.push(text)
        return out
    }
    let start = 0
    let i = 0
    while i <= len(text) - len(sep) {
        if slice(text, i, i + len(sep)) == sep {
            out.push(slice(text, start, i))
            i = i + len(sep)
            start = i
            continue
        }
        i = i + 1
    }
    out.push(slice(text, start, len(text)))
    out
}

func starts_with(string text, string prefix) bool {
    if len(text) < len(prefix) {
        return false
    }
    return slice(text, 0, len(prefix)) == prefix
}

func ends_with(string text, string suffix) bool {
    if len(text) < len(suffix) {
        return false
    }
    return slice(text, len(text) - len(suffix), len(text)) == suffix
}
