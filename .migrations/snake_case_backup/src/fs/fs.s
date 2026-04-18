package std.fs

use std.result.Result

struct fs_error {
    string message,
}

func read_to_string(string path) Result[string, fs_error] {
    __host_read_to_string(path)
}

func write_text_file(string path, string contents) Result[(), fs_error] {
    __host_write_text_file(path, contents)
}

func make_temp_dir(string prefix) Result[string, fs_error] {
    __host_make_temp_dir(prefix)
}

func read_to_string(string path) Result[string, fs_error] {
    read_to_string(path)
}

extern "intrinsic" func __host_read_to_string(string path) Result[string, fs_error]

extern "intrinsic" func __host_write_text_file(string path, string contents) Result[(), fs_error]

extern "intrinsic" func __host_make_temp_dir(string prefix) Result[string, fs_error]
