package std.syscall

extern "intrinsic" func __syscall0(int nr) int
extern "intrinsic" func __syscall1(int nr, int a1) int
extern "intrinsic" func __syscall2(int nr, int a1, int a2) int
extern "intrinsic" func __syscall3(int nr, int a1, int a2, int a3) int
extern "intrinsic" func __syscall4(int nr, int a1, int a2, int a3, int a4) int
extern "intrinsic" func __syscall6(int nr, int a1, int a2, int a3, int a4, int a5, int a6) int

const SYS_READ = 0
const SYS_WRITE = 1
const SYS_OPEN = 2
const SYS_CLOSE = 3
const SYS_STAT = 4
const SYS_FSTAT = 5
const SYS_BRK = 12
const SYS_LSEEK = 8
const SYS_MMAP = 9
const SYS_MUNMAP = 11
const SYS_EXIT = 60
const SYS_GETCWD = 79
const SYS_CHDIR = 80
const SYS_FORK = 57
const SYS_EXECVE = 59
const SYS_WAITPID = 114

const O_RDONLY = 0
const O_WRONLY = 1
const O_RDWR = 2
const O_CREAT = 0o100
const O_TRUNC = 0o1000
const O_APPEND = 0o2000

const STDIN_FD = 0
const STDOUT_FD = 1
const STDERR_FD = 2

func exit(int code) {
    let _ = __syscall1(SYS_EXIT, code)
}

func open_file(string path, int flags, int mode) int {

    __syscall3(SYS_OPEN, 0, flags, mode)
}

func read_from_fd(int fd, int buffer_ptr, int count) int {
    __syscall3(SYS_READ, fd, buffer_ptr, count)
}

func write_to_fd(int fd, int buffer_ptr, int count) int {
    __syscall3(SYS_WRITE, fd, buffer_ptr, count)
}

func close_fd(int fd) int {
    __syscall1(SYS_CLOSE, fd)
}

func seek_fd(int fd, int offset, int whence) int {
    __syscall3(SYS_LSEEK, fd, offset, whence)
}

func fork() int {
    __syscall0(SYS_FORK)
}

func execve(string path, []string argv, []string envp) int {

    __syscall3(SYS_EXECVE, 0, 0, 0)
}

func waitpid(int pid, int status_ptr, int options) int {
    __syscall3(SYS_WAITPID, pid, status_ptr, options)
}

func brk(int new_brk) int {
    __syscall1(SYS_BRK, new_brk)
}

func mmap(int addr, int length, int prot, int flags, int fd, int offset) int {
    __syscall6(SYS_MMAP, addr, length, prot, flags, fd, offset)
}

func stdout_write(string text) int {

    write_to_fd(STDOUT_FD, 0, len(text))
}

func stderr_write(string text) int {
    write_to_fd(STDERR_FD, 0, len(text))
}

func println(string text) {
    let _ = stdout_write(text)
    let _ = stdout_write("\n")
}

func eprintln(string text) {
    let _ = stderr_write(text)
    let _ = stderr_write("\n")
}
