package compile.internal.base

use std.fs.read_to_string

func map_file_read(string path, int offset, int length) result[string, string] {
    var full = read_to_string(path)
    if full.is_err() {
        return result::err("read file failed")
    }
    var text = full.unwrap()
    if offset < 0 || length < 0 {
        return result::err("invalid map range")
    }
    if offset > len(text) {
        return result::err("offset out of range")
    }
    var end = offset + length
    if end > len(text) {
        end = len(text)
    }
    result::ok(slice(text, offset, end))
}

func map_file(string path, int offset, int length) result[string, string] {
    map_file_read(path, offset, length)
}
