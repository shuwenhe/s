package std.fs
import (
    "std.result"
)
struct fs_error {
    string message
}

func read_to_string(string path) (string, fs_error) {
    return __host_read_to_string_with_error(path)
}

func write_text_file(string path, string contents) ((), fs_error) {
    return __host_write_text_file_with_error(path, contents)
}

func make_temp_dir(string prefix) (string, fs_error) {
    return __host_make_temp_dir_with_error(prefix)
}
extern "intrinsic" func __host_read_to_string_with_error(string path) (string, fs_error)
extern "intrinsic" func __host_write_text_file_with_error(string path, string contents) ((), fs_error)
extern "intrinsic" func __host_make_temp_dir_with_error(string prefix) (string, fs_error)
