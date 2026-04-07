package compiler.internal.backend

use compiler.internal.ssagen.MachineProgram
use std.result.Result

// GenBackend generates target object from a machine program (stub).
func GenBackend(program MachineProgram, outputPath String) Result[(), String] {
    // placeholder implementation
    Result::Err("backend not implemented")
}
