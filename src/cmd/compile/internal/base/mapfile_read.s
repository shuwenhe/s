package compile.internal.base
import (
    "std.fs"
)
func map_file_read(string path, int offset, int length) (string, string) {
    full, read_err := std.fs.read_to_string(path)
    if read_err.message != "" {
        return "", "read file failed: " + read_err.message
    }
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
