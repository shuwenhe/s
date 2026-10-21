package compile.internal.base
import (
    "std.fs"
)
func map_file_read(string path, int offset, int length) (string, string) {
    full_result := std.fs.read_to_string(path)
    if full_result.is_err() {
        return "", "read file failed"
    }
    full := full_result.unwrap()
    if offset < 0 || length < 0 {
        return "", "invalid map range"
    }
    if offset > len(full) {
        return "", "offset out of range"
    }
    end := offset + length
    if end > len(full) {
        end = len(full)
    }
    return prelude_slice(full, offset, end), ""
}

func map_file(string path, int offset, int length) (string, string) {
    return map_file_read(path, offset, length)
}
