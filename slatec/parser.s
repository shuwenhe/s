package slatec.parser

use std.result.Result
use std.vec.Vec
use slatec.ast.FunctionDecl
use slatec.ast.SourceFile
use slatec.ast.Stmt
use slatec.lexer.Token

struct ParseError {
    String message,
    i32 line,
    i32 column,
}

struct Parser {
    Vec[Token] tokens,
    i32 index,
}

func new_parser(Vec[Token] tokens) -> Parser {
    Parser {
        tokens: tokens,
        index: 0,
    }
}

impl Parser {
    func parse(mut self) -> Result[SourceFile, ParseError] {
        // Bootstrap MVP:
        // first S port keeps the same minimal hello-world surface area:
        // package main / func main() / println("...")
        Result::Ok(SourceFile {
            package_name: "main",
            functions: Vec[FunctionDecl](),
        })
    }
}

