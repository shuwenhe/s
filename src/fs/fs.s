package std.fs

use std.result.Result

struct FsError {
    String message,
}

func ReadToString(String path) Result[String, FsError] {
    __host_read_to_string(path)
}

func WriteTextFile(String path, String contents) Result[(), FsError] {
    __host_write_text_file(path, contents)
}

func MakeTempDir(String prefix) Result[String, FsError] {
    __host_make_temp_dir(prefix)
}

func read_to_string(String path) Result[String, FsError] {
    ReadToString(path)
}

extern "intrinsic" func __host_read_to_string(String path) Result[String, FsError]

extern "intrinsic" func __host_write_text_file(String path, String contents) Result[(), FsError]

extern "intrinsic" func __host_make_temp_dir(String prefix) Result[String, FsError]
