package std.fs

use std.result.Result

pub struct FsError {
    message: String,
}

fn read_to_string(path: String) -> Result[String, FsError] {
    Result::Err(FsError {
        message: "read_to_string is not implemented yet",
    })
}
