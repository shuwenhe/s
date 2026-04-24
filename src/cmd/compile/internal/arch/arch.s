package compile.internal.arch

use std.vec.vec

struct arch_dispatch_entry {
    string goarch
    string init_name
}

func dispatch_init(string arch) string {
    var init_name = lookup_init_name(arch)
    if init_name == "" {
        return "unknown architecture \"" + arch + "\""
    }
    run_arch_init(init_name)
}

// Backward-compatible wrapper for existing callers.
func init(string arch) string {
    return dispatch_init(arch)
}

func lookup_init_name(string arch) string {
    var table = arch_inits()
    var i = 0
    while i < table.len() {
        if table[i].goarch == arch {
            return table[i].init_name
        }
        i = i + 1
    }
    ""
}

func arch_inits() vec[arch_dispatch_entry] {
    var entries = vec[arch_dispatch_entry]()
    entries.push(arch_dispatch_entry { goarch: "386", init_name: "x86_init" })
    entries.push(arch_dispatch_entry { goarch: "amd64", init_name: "amd64_init" })
    entries.push(arch_dispatch_entry { goarch: "arm", init_name: "arm_init" })
    entries.push(arch_dispatch_entry { goarch: "arm64", init_name: "arm64_init" })
    entries.push(arch_dispatch_entry { goarch: "loong64", init_name: "loong64_init" })
    entries.push(arch_dispatch_entry { goarch: "mips", init_name: "mips_init" })
    entries.push(arch_dispatch_entry { goarch: "mipsle", init_name: "mips_init" })
    entries.push(arch_dispatch_entry { goarch: "mips64", init_name: "mips64_init" })
    entries.push(arch_dispatch_entry { goarch: "mips64le", init_name: "mips64_init" })
    entries.push(arch_dispatch_entry { goarch: "ppc64", init_name: "ppc64_init" })
    entries.push(arch_dispatch_entry { goarch: "ppc64le", init_name: "ppc64_init" })
    entries.push(arch_dispatch_entry { goarch: "riscv64", init_name: "riscv64_init" })
    entries.push(arch_dispatch_entry { goarch: "amd64p32", init_name: "amd64p32_init" })
    entries.push(arch_dispatch_entry { goarch: "s390x", init_name: "s390x_init" })
    entries.push(arch_dispatch_entry { goarch: "wasm", init_name: "wasm_init" })
    entries
}

func run_arch_init(string init_name) string {
    if init_name == "x86_init" {
        return x86_init()
    }
    if init_name == "amd64_init" {
        return amd64_init()
    }
    if init_name == "arm_init" {
        return arm_init()
    }
    if init_name == "arm64_init" {
        return arm64_init()
    }
    if init_name == "loong64_init" {
        return loong64_init()
    }
    if init_name == "mips_init" {
        return mips_init()
    }
    if init_name == "mips64_init" {
        return mips64_init()
    }
    if init_name == "ppc64_init" {
        return ppc64_init()
    }
    if init_name == "riscv64_init" {
        return riscv64_init()
    }
    if init_name == "amd64p32_init" {
        return amd64p32_init()
    }
    if init_name == "s390x_init" {
        return s390x_init()
    }
    if init_name == "wasm_init" {
        return wasm_init()
    }
    "unknown architecture init \"" + init_name + "\""
}

func amd64_init() string {
    ""
}

func x86_init() string {
    not_wired("386")
}

func arm_init() string {
    not_wired("arm")
}

func arm64_init() string {
    ""
}

func loong64_init() string {
    not_wired("loong64")
}

func mips_init() string {
    not_wired("mips/mipsle")
}

func mips64_init() string {
    not_wired("mips64/mips64le")
}

func ppc64_init() string {
    not_wired("ppc64/ppc64le")
}

func riscv64_init() string {
    ""
}

func amd64p32_init() string {
    ""
}

func s390x_init() string {
    ""
}

func wasm_init() string {
    ""
}

func not_wired(string arch) string {
    return "architecture \"" + arch + "\" is recognized but not wired to backend yet"
}
