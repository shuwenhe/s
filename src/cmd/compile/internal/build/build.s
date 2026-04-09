package compile.internal.build

use compile.internal.build.exec.ExecError
use compile.internal.build.exec.Run as RunCommand
use compile.internal.build.parse.ParseOptions
use compile.internal.build.parse.Usage
use compile.internal.build.report.Error as ReportError
use compile.internal.build.report.Usage as ReportUsage
use std.result.Result
use std.vec.Vec

func Main(Vec[String] args) i32 {
    match Run(args) {
        Result::Ok(()) => 0,
        Result::Err(err) => {
            ReportError(err.message)
            1
        }
    }
}

func Run(Vec[String] args) Result[(), ExecError] {
    match ParseOptions(args) {
        Result::Ok(options) => {
            if options.command == "help" {
                ReportUsage(Usage())
                return Result::Ok(())
            }
            match RunCommand(options) {
                Result::Ok(()) => Result::Ok(()),
                Result::Err(err) => Result::Err(convert_exec_error(err.message)),
            }
        }
        Result::Err(err) => Result::Err(convert_parse_error(err.message)),
    }
}

func convert_parse_error(String message) ExecError {
    ExecError {
        message: message,
    }
}

func convert_exec_error(String message) ExecError {
    ExecError {
        message: message,
    }
}
