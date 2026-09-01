package std.fs
use std.result.result
struct fs_error {
    string message
}

func read_to_string(string path) (string, fs_error) {
    __host_read_to_string(path)
}

func write_text_file(string path, string contents) ((), fs_error) {
    __host_write_text_file(path, contents)
}

func make_temp_dir(string prefix) (string, fs_error) {
    __host_make_temp_dir(prefix)
}
extern "intrinsic" func __host_read_to_string(string path) (string, fs_error)
extern "intrinsic" func __host_write_text_file(string path, string contents) ((), fs_error)
extern "intrinsic" func __host_make_temp_dir(string prefix) (string, fs_error)
