package compile.internal.arch

use compile.internal.amd64.Init as amd64Init
use compile.internal.amd64p32.Init as amd64p32Init
use compile.internal.arm64.Init as arm64Init
use internal.buildcfg.BuildCfgError
use compile.internal.riscv64.Init as riscv64Init
use compile.internal.s390x.Init as s390xInit
use compile.internal.wasm.Init as wasmInit
use std.result.Result

func Init(String arch) Result[(), BuildCfgError] {
    if arch == "amd64" {
        amd64Init()
        return Result::Ok(())
    }

    if arch == "arm64" {
        arm64Init()
        return Result::Ok(())
    }

    if arch == "riscv64" {
        riscv64Init()
        return Result::Ok(())
    }

    if arch == "amd64p32" {
        amd64p32Init()
        return Result::Ok(())
    }

    if arch == "s390x" {
        s390xInit()
        return Result::Ok(())
    }

    if arch == "wasm" {
        wasmInit()
        return Result::Ok(())
    }

    Result::Err(BuildCfgError {
        message: "unknown architecture \"" + arch + "\"",
    })
}
