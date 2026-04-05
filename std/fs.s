package std.fs

use std.result.Result

struct FsError {
    message: String,
}

func ReadToString(path: String) -> Result[String, FsError] {
    __host_read_to_string(path)
}

func WriteTextFile(path: String, contents: String) -> Result[(), FsError] {
    __host_write_text_file(path, contents)
}

func MakeTempDir(prefix: String) -> Result[String, FsError] {
    __host_make_temp_dir(prefix)
}

func read_to_string(path: String) -> Result[String, FsError] {
    ReadToString(path)
}

extern "intrinsic" func __host_read_to_string(path: String) -> Result[String, FsError]

extern "intrinsic" func __host_write_text_file(path: String, contents: String) -> Result[(), FsError]

extern "intrinsic" func __host_make_temp_dir(prefix: String) -> Result[String, FsError]
