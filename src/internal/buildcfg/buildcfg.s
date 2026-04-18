package internal.buildcfg

struct build_cfg_error {
    string message,
}

struct target {
    string goos,
    string goarch,
}

struct toolchain {
    string compiler,
    string assembler,
    string linker,
    string archiver,
}

struct build_cfg {
    target target,
    toolchain toolchain,
}

func goos() string {
    "linux"
}

func goarch() string {
    "amd64"
}

func check() string {
    ""
}
