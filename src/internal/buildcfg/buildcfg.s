package internal.buildcfg

struct BuildCfgError {
    String message,
}

struct Target {
    String goos,
    String goarch,
}

struct Toolchain {
    String compiler,
    String assembler,
    String linker,
    String archiver,
}

struct BuildCfg {
    Target target,
    Toolchain toolchain,
}

func GOOS() -> String {
    "linux"
}

func GOARCH() -> String {
    "amd64"
}

func Check() -> String {
    ""
}
