package compile.internal.build.exec

use compile.internal.build.backend.Build as BuildBinary
use compile.internal.build.backend.BackendError as BackendError
use compile.internal.build.backend.Run as RunBinary
use compile.internal.build.emit.Ast as EmitAst
use compile.internal.build.emit.Built as EmitBuilt
use compile.internal.build.emit.CheckOk as EmitCheckOk
use compile.internal.build.emit.Tokens as EmitTokens
use compile.internal.build.frontend.FrontendError as FrontendError
use compile.internal.build.frontend.Load as LoadFrontend
use compile.internal.build.parse.CompileOptions
use std.result.Result

struct ExecError {
    String message,
}

func Run(CompileOptions options) -> Result[(), ExecError] {
    if options.command == "help" {
        return Result::Ok(())
    }

    var frontend =
        match LoadFrontend(options.path) {
            Result::Ok(value) => value,
            Result::Err(err) => {
                return Result::Err(convert_frontend_error(err))
            }
        }

    if options.command == "check" {
        EmitCheckOk(options.path)
        return Result::Ok(())
    }

    if options.command == "tokens" {
        EmitTokens(frontend.tokens)
        return Result::Ok(())
    }

    if options.command == "ast" {
        EmitAst(frontend.ast)
        return Result::Ok(())
    }

    if options.command == "build" {
        match BuildBinary(options.path, options.output) {
            Result::Ok(()) => {
                EmitBuilt(options.output)
                return Result::Ok(())
            }
            Result::Err(err) => {
                return Result::Err(convert_backend_error(err))
            }
        }
    }

    if options.command == "run" {
        match RunBinary(options.path) {
            Result::Ok(()) => Result::Ok(()),
            Result::Err(err) => Result::Err(convert_backend_error(err)),
        }
    } else {
        Result::Err(ExecError {
            message: "unknown command: " + options.command,
        })
    }
}

func convert_frontend_error(FrontendError err) -> ExecError {
    ExecError {
        message: err.message,
    }
}

func convert_backend_error(BackendError err) -> ExecError {
    ExecError {
        message: err.message,
    }
}
