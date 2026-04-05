package compiler.backend_elf64

use frontend.SourceFile
use std.result.Result

struct BackendError {
    message: String,
}

func build_executable(SourceFile source, String output_path) -> Result[(), BackendError] {
    // Minimal backend design:
    // 1. compile SourceFile -> linear ProgramOp list
    // 2. emit Linux x86_64 assembly text
    // 3. invoke host as/ld through runtime boundary
    //
    // See /app/s/docs/backend_elf64.md for the executable MVP plan.
    //
    // The runnable algorithm still lives in backend_elf64.py today.
    source
    output_path
    Result::Err(BackendError {
        message: "S backend bootstrap not wired yet",
    })
}
