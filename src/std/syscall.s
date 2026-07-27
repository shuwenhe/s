package std.syscall

// Linux x86-64 System Call Interface
// Provides low-level syscall wrappers for pure S implementation

// Raw syscall intrinsics (compiler generates syscall instruction)
extern "intrinsic" func __syscall0(int nr) int
extern "intrinsic" func __syscall1(int nr, int a1) int
extern "intrinsic" func __syscall2(int nr, int a1, int a2) int
extern "intrinsic" func __syscall3(int nr, int a1, int a2, int a3) int
extern "intrinsic" func __syscall4(int nr, int a1, int a2, int a3, int a4) int
extern "intrinsic" func __syscall6(int nr, int a1, int a2, int a3, int a4, int a5, int a6) int

// Linux x86-64 syscall numbers
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

// File open flags (from fcntl.h)
const O_RDONLY = 0
const O_WRONLY = 1
const O_RDWR = 2
const O_CREAT = 0o100
const O_TRUNC = 0o1000
const O_APPEND = 0o2000

// File descriptors
const STDIN_FD = 0
const STDOUT_FD = 1
const STDERR_FD = 2

// === Process Control ===
func exit(int code) {
    let _ = __syscall1(SYS_EXIT, code)
}

// === File I/O Syscalls ===

// open(path, flags, mode) → fd
func open_file(string path, int flags, int mode) int {
    // Convert S string to C string pointer
    // (requires compiler intrinsic support for string→ptr)
    __syscall3(SYS_OPEN, 0, flags, mode)
}

// read(fd, buffer, count) → bytes_read
func read_from_fd(int fd, int buffer_ptr, int count) int {
    __syscall3(SYS_READ, fd, buffer_ptr, count)
}

// write(fd, buffer, count) → bytes_written  
func write_to_fd(int fd, int buffer_ptr, int count) int {
    __syscall3(SYS_WRITE, fd, buffer_ptr, count)
}

// close(fd) → 0 or error
func close_fd(int fd) int {
    __syscall1(SYS_CLOSE, fd)
}

// lseek(fd, offset, whence) → new_offset
func seek_fd(int fd, int offset, int whence) int {
    __syscall3(SYS_LSEEK, fd, offset, whence)
}

// === Process Execution ===

// fork() → pid (0 in child, child_pid in parent, -1 on error)
func fork() int {
    __syscall0(SYS_FORK)
}

// execve(path, argv, envp) → never returns on success, -1 on error
func execve(string path, []string argv, []string envp) int {
    // Requires compiler support for array→pointer conversion
    __syscall3(SYS_EXECVE, 0, 0, 0)
}

// waitpid(pid, status_ptr, options) → pid or error
func waitpid(int pid, int status_ptr, int options) int {
    __syscall3(SYS_WAITPID, pid, status_ptr, options)
}

// === Memory Management (future) ===

// brk(new_brk) → actual_brk
func brk(int new_brk) int {
    __syscall1(SYS_BRK, new_brk)
}

// mmap(addr, length, prot, flags, fd, offset) → ptr or error
func mmap(int addr, int length, int prot, int flags, int fd, int offset) int {
    __syscall6(SYS_MMAP, addr, length, prot, flags, fd, offset)
}

// === Utilities ===

// Write string to stdout
func stdout_write(string text) int {
    // TODO: Need compiler support for string→buffer
    write_to_fd(STDOUT_FD, 0, len(text))
}

// Write string to stderr  
func stderr_write(string text) int {
    write_to_fd(STDERR_FD, 0, len(text))
}

// Convenience
func println(string text) {
    let _ = stdout_write(text)
    let _ = stdout_write("\n")
}

func eprintln(string text) {
    let _ = stderr_write(text)
    let _ = stderr_write("\n")
}
