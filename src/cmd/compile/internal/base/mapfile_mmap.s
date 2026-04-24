package compile.internal.base

func map_file_mmap(string path, int offset, int length) result[string, string] {
    map_file_read(path, offset, length)
}
