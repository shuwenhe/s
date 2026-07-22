
func dup_cstr(text: string): string {
    if text == nil {
        return nil
    }
    return text
}

func host_fs_free(ptr: string) {
}

func mkdirs_for_path(path: string) {
    if path == nil || path == "" {
        return
    }
    let parts = path.split("/")
    let current = ""
    for part in parts {
        if part == "" {
            continue
        }
        current = current + "/" + part
        os.mkdir(current, 0o755)
    }
}

func host_fs_read_to_string(path: string): string {
    if path == nil {
        return nil
    }
    return os.read_file(path)
}

func host_fs_write_text_file(path: string, contents: string): int {
    if path == nil || contents == nil {
        return -1
    }
    mkdirs_for_path(path)
    os.write_file(path, contents)
    return 0
}

func host_fs_make_temp_dir(prefix: string, base_dir: string): string {
    let prefix_text = if prefix == nil { "tmp-" } else { prefix }
    let root = if base_dir == nil { "/tmp" } else { base_dir }
    mkdirs_for_path(root)
    return os.make_temp_dir(prefix_text, root)
}
