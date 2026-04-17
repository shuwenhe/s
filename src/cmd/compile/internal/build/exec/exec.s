package compile.internal.build.exec

use compile.internal.backend.Build as BuildBinary
use compile.internal.backend.Run as RunBinary
use compile.internal.build.emit.Ast as EmitAst
use compile.internal.build.emit.Built as EmitBuilt
use compile.internal.build.emit.CheckOk as EmitCheckOk
use compile.internal.build.emit.Tokens as EmitTokens
use compile.internal.semantic.CheckText
use compile.internal.syntax.ParseSource
use compile.internal.syntax.ReadSource
use compile.internal.syntax.Tokenize
use compile.internal.build.parse.CompileOptions
use std.result.Result

struct ExecError {
    String message,
}

func Run(CompileOptions options) -> Result[(), ExecError] {
    if options.command == "help" {
        return Result::Ok(())
    }

    var source_result = ReadSource(options.path)
    if source_result.is_err() {
        return Result::Err(new_exec_error())
    }

    var source = source_result.unwrap()
    if options.command == "check" {
        var parse_result = ParseSource(source)
        if parse_result.is_err() {
            return Result::Err(new_exec_error())
        }
        if CheckText(source) != 0 {
            return Result::Err(new_exec_error())
        }
        EmitCheckOk(options.path)
        return Result::Ok(())
    }

    if options.command == "tokens" {
        var tokens_result = Tokenize(source)
        if tokens_result.is_err() {
            return Result::Err(new_exec_error())
        }
        EmitTokens(tokens_result.unwrap())
        return Result::Ok(())
    }

    if options.command == "ast" {
        var ast_result = ParseSource(source)
        if ast_result.is_err() {
            return Result::Err(new_exec_error())
        }
        EmitAst(ast_result.unwrap())
        return Result::Ok(())
    }

    if options.command == "build" {
        var build_result = BuildBinary(options.path, options.output)
        if build_result.is_ok() {
            EmitBuilt(options.output)
            return Result::Ok(())
        }
        return Result::Err(new_exec_error())
    }

    if options.command == "run" {
        var run_result = RunBinary(options.path)
        if run_result.is_ok() {
            return Result::Ok(())
        }
        return Result::Err(new_exec_error())
    }

    Result::Err(new_exec_error())
}

func new_exec_error() -> ExecError {
    ExecError {
        message: "",
    }
}
