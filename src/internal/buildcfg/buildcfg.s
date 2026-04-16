package internal.buildcfg

use std.env.Get
use std.result.Result

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

func Current() BuildCfg {
    BuildCfg {
        target: Target {
            goos: Get("GOOS").unwrap_or("linux"),
            goarch: Get("GOARCH").unwrap_or("amd64"),
        },
        toolchain: Toolchain {
            compiler: Get("CC").unwrap_or("cc"),
            assembler: Get("AS").unwrap_or("as"),
            linker: Get("LD").unwrap_or("ld"),
            archiver: Get("AR").unwrap_or("ar"),
        },
    }
}

func GOOS() String {
    Current().target.goos
}

func GOARCH() String {
    Current().target.goarch
}

func Check() Result[(), BuildCfgError] {
    var cfg = Current()
    var goos = cfg.target.goos
    var goarch = cfg.target.goarch

    if goos != "linux" {
        return Result::Err(BuildCfgError {
            message: "unsupported GOOS: " + goos,
        })
    }

    if goarch != "amd64" && goarch != "arm64" && goarch != "riscv64" && goarch != "amd64p32" {
        return Result::Err(BuildCfgError {
            message: "unsupported GOARCH: " + goarch,
        })
    }

    Result::Ok(())
}
