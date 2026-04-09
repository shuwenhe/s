package compile.internal.build.backend

use compile.internal.backend.Build as BuildBinary
use compile.internal.backend.CliError as BackendCliError
use compile.internal.backend.Run as RunBinary
use std.result.Result

struct BackendError {
    String message,
}

func Build(String path, String output) Result[(), BackendError] {
    match BuildBinary(path, output) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => Result::Err(convert_backend_error(err)),
    }
}

func Run(String path) Result[(), BackendError] {
    match RunBinary(path) {
        Result::Ok(()) => Result::Ok(()),
        Result::Err(err) => Result::Err(convert_backend_error(err)),
    }
}

func convert_backend_error(BackendCliError err) BackendError {
    BackendError {
        message: err.message,
    }
}
