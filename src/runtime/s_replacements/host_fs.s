// S 实现：host_fs.c
// 提供文件读写、目录创建、临时目录等功能

fn dup_cstr(text: string): string {
    if text == nil {
        return nil
    }
    return text // S 语言字符串为不可变对象，直接返回即可
}

fn host_fs_free(ptr: string) {
    // S 语言自动垃圾回收，无需手动释放
}

fn mkdirs_for_path(path: string) {
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

fn host_fs_read_to_string(path: string): string {
    if path == nil {
        return nil
    }
    return os.read_file(path)
}

fn host_fs_write_text_file(path: string, contents: string): int {
    if path == nil || contents == nil {
        return -1
    }
    mkdirs_for_path(path)
    os.write_file(path, contents)
    return 0
}

fn host_fs_make_temp_dir(prefix: string, base_dir: string): string {
    let prefix_text = if prefix == nil { "tmp-" } else { prefix }
    let root = if base_dir == nil { "/tmp" } else { base_dir }
    mkdirs_for_path(root)
    return os.make_temp_dir(prefix_text, root)
}
