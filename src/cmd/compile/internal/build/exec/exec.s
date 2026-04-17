package compile.internal.build.exec

use std.io.eprintln
use compile.internal.build.emit.Ast as EmitAst
use compile.internal.build.emit.Built as EmitBuilt
use compile.internal.build.emit.CheckOk as EmitCheckOk
use compile.internal.build.emit.Tokens as EmitTokens
use compile.internal.semantic.CheckText
use compile.internal.syntax.ParseSource
use compile.internal.syntax.ReadSource
use compile.internal.syntax.Tokenize
use compile.internal.build.parse.CompileOptions

func Run(CompileOptions options) -> i32 {
    if options.command == "help" {
        return 0
    }

    var source_result = ReadSource(options.path)
    if source_result.is_err() {
        return 1
    }

    var source = source_result.unwrap()
    if options.command == "check" {
        var parse_result = ParseSource(source)
        if parse_result.is_err() {
            return 1
        }
        if CheckText(source) != 0 {
            return 1
        }
        EmitCheckOk(options.path);
        return 0
    }

    if options.command == "tokens" {
        var tokens_result = Tokenize(source)
        if tokens_result.is_err() {
            return 1
        }
        EmitTokens(tokens_result.unwrap());
        return 0
    }

    if options.command == "ast" {
        var ast_result = ParseSource(source)
        if ast_result.is_err() {
            return 1
        }
        EmitAst(ast_result.unwrap());
        return 0
    }

    if options.command == "build" {
        eprintln("error: build command depends on deprecated backend module; use hosted compiler or self-hosted build path")
        return 1
    }

    if options.command == "run" {
        eprintln("error: run command depends on deprecated backend module; run compiled binaries directly or use the hosted runner")
        return 1
    }

    1
}
