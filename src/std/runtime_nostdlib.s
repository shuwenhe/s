package std.runtime_nostdlib

// Pure S implementation of minimal runtime library
// Replaces C libc for self-hosted compiler bootstrap
// 
// This provides:
// - Process exit
// - File I/O via syscalls
// - Minimal memory allocation
// - No C library dependencies

// System call interface for Linux x86-64
// These are intrinsic functions that the compiler understands

extern "intrinsic" func __syscall(int nr, int arg1, int arg2, int arg3, int arg4, int arg5, int arg6) int

// Linux x86-64 syscall numbers
const SYS_EXIT = 60
const SYS_WRITE = 1
const SYS_READ = 0
const SYS_OPEN = 2
const SYS_CLOSE = 3
const SYS_BRK = 12

// File descriptor constants
const STDIN_FILENO = 0
const STDOUT_FILENO = 1
const STDERR_FILENO = 2

// Exit the process
func exit(int status) {
    __syscall(SYS_EXIT, status, 0, 0, 0, 0, 0)
}

// Write bytes to file descriptor
func write_fd(int fd, []byte buffer) int {
    if len(buffer) == 0 {
        return 0
    }
    
    // TODO: Need to pass pointer to buffer
    // For now, assume compiler handles this
    return __syscall(SYS_WRITE, fd, 0, len(buffer), 0, 0, 0)
}

// Write string to stdout
func stdout_write(string text) int {
    if len(text) == 0 {
        return 0
    }
    return write_fd(STDOUT_FILENO, []byte(text))
}

// Write string to stderr
func stderr_write(string text) int {
    if len(text) == 0 {
        return 0
    }
    return write_fd(STDERR_FILENO, []byte(text))
}

// Minimal memory allocator using brk syscall
var heap_break: i64 = 0

func brk(i64 new_break) i64 {
    // Call brk syscall to extend or check heap
    return i64(__syscall(SYS_BRK, int(new_break), 0, 0, 0, 0, 0))
}

func malloc(int size) &byte {
    // This is a simplified allocator
    // For compiler bootstrap, we don't need sophisticated allocation
    // Just request more heap space with brk
    
    if heap_break == 0 {
        heap_break = brk(0)  // Get current break
    }
    
    let new_break = heap_break + i64(size)
    let result = brk(new_break)
    
    if result < 0 {
        return nil  // Allocation failed
    }
    
    let allocated = heap_break
    heap_break = new_break
    
    return &byte(allocated)
}

func free(&byte ptr) {
    // No-op for simple bump allocator
    // In a production runtime, we would track freed regions
}

// Print formatted output (minimal version)
func print(string text) {
    let _ = stdout_write(text)
}

func println(string text) {
    let _ = stdout_write(text + "\n")
}

// Error output
func eprint(string text) {
    let _ = stderr_write(text)
}

func eprintln(string text) {
    let _ = stderr_write(text + "\n")
}

// Entry point for standalone programs
// This replaces the C runtime initialization
func __start() int {
    // Call the main function (provided by user program)
    return main()
}

// Declare main function (user-provided)
extern func main() int
