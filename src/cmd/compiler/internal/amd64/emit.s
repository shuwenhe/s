package compiler.internal.amd64

use compiler.backend_elf64.BackendError
use compiler.backend_elf64.EmitProgram
use compiler.internal.ssagen.MachineProgram
use std.result.Result

func ArchName() String {
    "amd64"
}

func LinkProgram(MachineProgram program, String outputPath) Result[(), BackendError] {
    EmitProgram(program, outputPath)
}
