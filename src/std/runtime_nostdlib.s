package std.runtime_nostdlib

// Pure S implementation of minimal runtime library for -nostdlib builds
// Provides syscall interface and minimal utilities
// Linux x86-64 only

// System call intrinsic (compiler generates raw syscall)
extern "intrinsic" func syscall_6(int nr, int a1, int a2, int a3, int a4, int a5, int a6) int
extern "intrinsic" func syscall_1(int nr, int a1) int

// Linux x86-64 syscall numbers
const SYS_EXIT = 60
const SYS_WRITE = 1
const SYS_READ = 0
const SYS_OPEN = 2
const SYS_CLOSE = 3
const SYS_BRK = 12

// File descriptor constants
const STDIN_FD = 0
const STDOUT_FD = 1
const STDERR_FD = 2

// Process control
func exit(int code) {
    // Call exit(2) syscall
    let _ = syscall_1(SYS_EXIT, code)
}

// File I/O via syscalls
func write_to_fd(int fd, string text) int {
    // write(fd, buffer, count) syscall
    // Note: S compiler must handle string-to-pointer conversion
    let count = len(text)
    if count == 0 {
        return 0
    }
    syscall_6(SYS_WRITE, fd, 0, count, 0, 0, 0)
}

// Standard output
func stdout_write(string text) int {
    write_to_fd(STDOUT_FD, text)
}

// Standard error
func stderr_write(string text) int {
    write_to_fd(STDERR_FD, text)
}

// Convenience functions
func println(string text) {
    let _ = stdout_write(text)
    let _ = stdout_write("\n")
}

func eprintln(string text) {
    let _ = stderr_write(text)
    let _ = stderr_write("\n")
}

// Heap management (simple bump allocator)
var heap_top = 0x10000000  // 256MB offset for heap start

func malloc(int size) int {
    if size <= 0 {
        return 0
    }
    
    let ptr = heap_top
    heap_top = heap_top + size
    
    // Align to 16 bytes
    let remainder = heap_top % 16
    if remainder != 0 {
        heap_top = heap_top + (16 - remainder)
    }
    
    ptr
}

func free(int ptr) {
    // No-op for bump allocator
}

// Program entry (called by runtime startup)
// User code should define their own main()
extern func main() int

// Standard entry point for nostdlib programs
func __start() int {
    main()
}
