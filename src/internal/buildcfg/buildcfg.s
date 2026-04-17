package internal.buildcfg

struct BuildCfgError {
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

struct BuildCfg {
    Target target,
    Toolchain toolchain,
}

func GOOS() string {
    "linux"
}

func GOARCH() string {
    "amd64"
}

func Check() string {
    ""
}
