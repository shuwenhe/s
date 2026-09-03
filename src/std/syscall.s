package std.syscall
extern "intrinsic" func __syscall0(int nr) int
extern "intrinsic" func __syscall1(int nr, int a1) int
extern "intrinsic" func __syscall2(int nr, int a1, int a2) int
extern "intrinsic" func __syscall3(int nr, int a1, int a2, int a3) int
extern "intrinsic" func __syscall4(int nr, int a1, int a2, int a3, int a4) int
extern "intrinsic" func __syscall6(int nr, int a1, int a2, int a3, int a4, int a5, int a6) int
const sys_read = 0
const sys_write = 1
const sys_open = 2
const sys_close = 3
const sys_stat = 4
const sys_fstat = 5
const sys_brk = 12
const sys_lseek = 8
const sys_mmap = 9
const sys_munmap = 11
const sys_exit = 60
const sys_getcwd = 79
const sys_chdir = 80
const sys_fork = 57
const sys_execve = 59
const sys_waitpid = 114
const o_rdonly = 0
const o_wronly = 1
const o_rdwr = 2
const o_creat = 0o100
const o_trunc = 0o1000
const o_append = 0o2000
const stdin_fd = 0
const stdout_fd = 1
const stderr_fd = 2
func exit(int code) {
    _ := __syscall1(sys_exit, code)
}

func open_file(string path, int flags, int mode) int {
    __syscall3(sys_open, 0, flags, mode)
}

func read_from_fd(int fd, int buffer_ptr, int count) int {
    __syscall3(sys_read, fd, buffer_ptr, count)
}

func write_to_fd(int fd, int buffer_ptr, int count) int {
    __syscall3(sys_write, fd, buffer_ptr, count)
}

func close_fd(int fd) int {
    __syscall1(sys_close, fd)
}

func seek_fd(int fd, int offset, int whence) int {
    __syscall3(sys_lseek, fd, offset, whence)
}

func fork() int {
    __syscall0(sys_fork)
}

func execve(string path, []string argv, []string envp) int {
    __syscall3(sys_execve, 0, 0, 0)
}

func waitpid(int pid, int status_ptr, int options) int {
    __syscall3(sys_waitpid, pid, status_ptr, options)
}

func brk(int new_brk) int {
    __syscall1(sys_brk, new_brk)
}

func mmap(int addr, int length, int prot, int flags, int fd, int offset) int {
    __syscall6(sys_mmap, addr, length, prot, flags, fd, offset)
}

func stdout_write(string text) int {
    write_to_fd(stdout_fd, 0, len(text))
}

func stderr_write(string text) int {
    write_to_fd(stderr_fd, 0, len(text))
}

func println(string text) {
    _ := stdout_write(text)
    _ := stdout_write("\n")
}

func eprintln(string text) {
    _ := stderr_write(text)
    _ := stderr_write("\n")
}
