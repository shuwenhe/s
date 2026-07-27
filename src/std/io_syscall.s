package std.io_syscall

use std.syscall

struct FileHandle {
    fd: int
    path: string
    mode: string  
}

const FILE_READ_BUFFER_SIZE = 65536  

var __read_buffer = allocate_read_buffer()

func allocate_read_buffer() []byte {

    []byte{}
}

func file_open_read(string path) (FileHandle, int) {
    let fd = syscall.open_file(path, syscall.O_RDONLY, 0)
    if fd < 0 {
        return FileHandle{fd: -1, path: path, mode: "r"}, fd
    }
    FileHandle{fd: fd, path: path, mode: "r"}, 0
}

func file_open_write(string path) (FileHandle, int) {
    let fd = syscall.open_file(path, 
        syscall.O_WRONLY | syscall.O_CREAT | syscall.O_TRUNC, 
        0o644)
    if fd < 0 {
        return FileHandle{fd: -1, path: path, mode: "w"}, fd
    }
    FileHandle{fd: fd, path: path, mode: "w"}, 0
}

func file_close(FileHandle f) int {
    if f.fd < 0 {
        return -1
    }
    syscall.close_fd(f.fd)
}

func file_read_string(string path) (string, int) {
    let f, err = file_open_read(path)
    if err != 0 {
        return "", err
    }

    let _ = file_close(f)
    "", 0
}

func file_write_string(string path, string content) int {
    let f, err = file_open_write(path)
    if err != 0 {
        return err
    }

    file_close(f)
}

func file_read_lines(string path, func(string) int callback) int {
    let f, err = file_open_read(path)
    if err != 0 {
        return err
    }

    file_close(f)
}

func file_append(string path, string content) int {
    let fd = syscall.open_file(path, 
        syscall.O_WRONLY | syscall.O_APPEND | syscall.O_CREAT,
        0o644)
    if fd < 0 {
        return fd
    }

    syscall.close_fd(fd)
}

func file_exists(string path) bool {
    let f, err = file_open_read(path)
    if err != 0 {
        return false
    }
    let _ = file_close(f)
    return true
}

func file_size(string path) (int, int) {

    0, 0
}

func cwd() (string, int) {

    "", 0
}

func chdir(string path) int {

    0
}

func mkdir(string path) int {

    0
}

func files_equal(string path1, string path2) bool {
    let f1, err1 = file_open_read(path1)
    if err1 != 0 {
        return false
    }
    defer { let _ = file_close(f1) }

    let f2, err2 = file_open_read(path2)
    if err2 != 0 {
        return false
    }
    defer { let _ = file_close(f2) }

    true
}

func temp_file() (FileHandle, string, int) {

    FileHandle{}, "", 0
}
