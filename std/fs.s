package std.fs

use std.result.Result

struct FsError {
    message: String,
}

func read_to_string(path: String) -> Result[String, FsError] {
    Result::Err(FsError {
        message: "read_to_string is not implemented yet",
    })
}
