package slatec.backend_elf64

use std.result.Result
use slatec.ast.SourceFile

struct BackendError {
    String message,
}

func build_executable(SourceFile source, String output_path) -> Result[(), BackendError] {
    // Bootstrap plan:
    // 1. lower SourceFile -> Linux x86_64 assembly text
    // 2. invoke host assembler and linker
    // 3. return Result
    //
    // The executable implementation still lives in Python bootstrap code.
    // This S file is the self-hosted backend contract we will grow into.
    source
    output_path
    Result::Err(BackendError {
        message: "S backend bootstrap not wired yet",
    })
}

