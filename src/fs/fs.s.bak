package std.fs

use std.result.Result

struct FsError {
    string message,
}

func ReadToString(string path) Result[string, FsError] {
    __host_read_to_string(path)
}

func WriteTextFile(string path, string contents) Result[(), FsError] {
    __host_write_text_file(path, contents)
}

func MakeTempDir(string prefix) Result[string, FsError] {
    __host_make_temp_dir(prefix)
}

func readToString(string path) Result[string, FsError] {
    ReadToString(path)
}

extern "intrinsic" func __host_read_to_string(string path) Result[string, FsError]

extern "intrinsic" func __host_write_text_file(string path, string contents) Result[(), FsError]

extern "intrinsic" func __host_make_temp_dir(string prefix) Result[string, FsError]
