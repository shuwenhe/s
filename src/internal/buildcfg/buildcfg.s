package internal.buildcfg

use std.env.get
use std.prelude.len
use std.prelude.slice
use std.vec.vec

struct build_cfg_error {
    string message
}

struct target {
    string goos
    string goarch
}

struct toolchain {
    string compiler
    string assembler
    string linker
    string archiver
}

struct build_cfg {
    target target
    toolchain toolchain
}

func goos() string {
    let explicit_value = normalize_goos(first_non_empty_goos_env())
    if explicit_value != "" {
        return explicit_value
    }

    let inferred_value = infer_goos_from_host_env()
    if inferred_value != "" {
        return inferred_value
    }

    "linux"
}

func goarch() string {
    let explicit_value = normalize_goarch(first_non_empty_env())
    if explicit_value != "" {
        return explicit_value
    }

    let inferred_value = infer_goarch_from_host_env()
    if inferred_value != "" {
        return inferred_value
    }

    "amd64"
}

func check() string {
    let os = goos()
    if !is_supported_goos(os) {
        return "unsupported goos: " + os
    }

    let arch = goarch()
    if !is_supported_goarch(arch) {
        return "unsupported goarch: " + arch
    }
    ""
}

func first_non_empty_goos_env() string {
    let names = vec[string]()
    names.push("S_GOOS")
    names.push("s_goos")
    names.push("GOOS")

    let i = 0
    while i < names.len() {
        let value = get(names[i])
        switch value {
            some(raw) : {
                let text = trim_spaces(raw)
                if text != "" {
                    return text
                }
            }
            none : {},
        }
        i = i + 1
    }

    ""
}

func infer_goos_from_host_env() string {
    let names = vec[string]()
    names.push("OSTYPE")
    names.push("OS")
    names.push("VSCODE_CLI_OS")
    names.push("MSYSTEM")

    let i = 0
    while i < names.len() {
        let value = get(names[i])
        switch value {
            some(raw) : {
                let mapped = map_host_os(raw)
                if mapped != "" {
                    return mapped
                }
            }
            none : {},
        }
        i = i + 1
    }

    ""
}

func normalize_goos(string os) string {
    let mapped = map_host_os(os)
    if mapped != "" {
        return mapped
    }
    trim_spaces(os)
}

func map_host_os(string raw) string {
    let text = trim_spaces(raw)

    if contains_token(text, "linux") {
        return "linux"
    }
    if contains_token(text, "darwin") || contains_token(text, "mac") || contains_token(text, "osx") {
        return "darwin"
    }
    if contains_token(text, "windows")
        || contains_token(text, "win32")
        || contains_token(text, "msys")
        || contains_token(text, "mingw")
        || contains_token(text, "cygwin") {
        return "windows"
    }
    if contains_token(text, "freebsd") {
        return "freebsd"
    }

    ""
}

func is_supported_goos(string os) bool {
    os == "linux"
        || os == "darwin"
        || os == "windows"
        || os == "freebsd"
}

func first_non_empty_env() string {
    let names = vec[string]()
    names.push("S_GOARCH")
    names.push("s_goarch")
    names.push("GOARCH")

    let i = 0
    while i < names.len() {
        let value = get(names[i])
        switch value {
            some(raw) : {
                let text = trim_spaces(raw)
                if text != "" {
                    return text
                }
            }
            none : {},
        }
        i = i + 1
    }

    ""
}

func infer_goarch_from_host_env() string {
    let names = vec[string]()
    names.push("HOSTTYPE")
    names.push("MACHTYPE")
    names.push("PROCESSOR_ARCHITECTURE")
    names.push("VSCODE_CLI_ARCH")

    let i = 0
    while i < names.len() {
        let value = get(names[i])
        switch value {
            some(raw) : {
                let mapped = map_host_arch(raw)
                if mapped != "" {
                    return mapped
                }
            }
            none : {},
        }
        i = i + 1
    }

    ""
}

func normalize_goarch(string arch) string {
    let mapped = map_host_arch(arch)
    if mapped != "" {
        return mapped
    }
    trim_spaces(arch)
}

func map_host_arch(string raw) string {
    let text = trim_spaces(raw)

    if contains_token(text, "aarch64") || contains_token(text, "arm64") {
        return "arm64"
    }
    if contains_token(text, "x86_64") || contains_token(text, "amd64") || contains_token(text, "x64") {
        return "amd64"
    }
    if contains_token(text, "riscv64") {
        return "riscv64"
    }
    if contains_token(text, "s390x") {
        return "s390x"
    }
    if contains_token(text, "wasm") {
        return "wasm"
    }
    if contains_token(text, "amd64p32") {
        return "amd64p32"
    }

    ""
}

func is_supported_goarch(string arch) bool {
    arch == "amd64"
        || arch == "arm64"
        || arch == "riscv64"
        || arch == "amd64p32"
        || arch == "s390x"
        || arch == "wasm"
}

func contains_token(string text, string token) bool {
    if len(token) == 0 {
        return true
    }
    if len(text) < len(token) {
        return false
    }

    let i = 0
    let limit = len(text) - len(token)
    while i <= limit {
        if slice(text, i, i + len(token)) == token {
            return true
        }
        i = i + 1
    }

    false
}

func trim_spaces(string text) string {
    let start = 0
    let end = len(text)

    while start < end && is_space(slice(text, start, start + 1)) {
        start = start + 1
    }
    while end > start && is_space(slice(text, end - 1, end)) {
        end = end - 1
    }

    slice(text, start, end)
}

func is_space(string ch) bool {
    ch == " " || ch == "\t" || ch == "\n" || ch == "\r"
}
