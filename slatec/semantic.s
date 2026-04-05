package slatec.semantic

use std.result.Result
use slatec.ast.SourceFile

struct SemanticError {
    String message,
}

func check(SourceFile source) -> Result[(), SemanticError] {
    if source.package_name != "main" {
        return Result::Err(SemanticError {
            message: "hello-world MVP requires package main",
        })
    }
    Result::Ok(())
}

