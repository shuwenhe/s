package compile.internal.build.frontend

use compile.internal.check.CheckFrontend
use compile.internal.check.CliError as CheckCliError
use compile.internal.check.FrontendResult
use compile.internal.check.LoadFrontend
use std.result.Result

struct FrontendError {
    String message,
}

func Load(String path) -> Result[FrontendResult, FrontendError] {
    var frontend =
        match LoadFrontend(path) {
            Result::Ok(value) => value,
            Result::Err(err) => {
                return Result::Err(convert_check_error(err))
            }
        }

    match CheckFrontend(frontend) {
        Result::Ok(()) => Result::Ok(frontend),
        Result::Err(err) => Result::Err(convert_check_error(err)),
    }
}

func convert_check_error(CheckCliError err) -> FrontendError {
    FrontendError {
        message: err.message,
    }
}
