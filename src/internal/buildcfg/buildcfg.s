package internal.buildcfg

struct build_cfg_error {
    string message,
}

struct Target {
    string goos,
    string goarch,
}

struct Toolchain {
    string compiler,
    string assembler,
    string linker,
    string archiver,
}

struct build_cfg {
    Target target,
    Toolchain toolchain,
}

func goos() string {
    "linux"
}

func goarch() string {
    "amd64"
}

func Check() string {
    ""
}
