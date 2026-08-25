package std.runtime_nostdlib
extern "intrinsic" func syscall_6(int nr, int a1, int a2, int a3, int a4, int a5, int a6) int
extern "intrinsic" func syscall_1(int nr, int a1) int
const SYS_EXIT = 60
const SYS_WRITE = 1
const SYS_READ = 0
const SYS_OPEN = 2
const SYS_CLOSE = 3
const SYS_BRK = 12
const STDIN_FD = 0
const STDOUT_FD = 1
const STDERR_FD = 2

func exit(int code) {
    _ := syscall_1(SYS_EXIT, code)
}

func write_to_fd(int fd, string text) int {
    count := len(text)
    if count == 0 {
        return 0
    }
    syscall_6(SYS_WRITE, fd, 0, count, 0, 0, 0)
}

func stdout_write(string text) int {
    write_to_fd(STDOUT_FD, text)
}

func stderr_write(string text) int {
    write_to_fd(STDERR_FD, text)
}

func println(string text) {
    _ := stdout_write(text)
    _ := stdout_write("\n")
}

func eprintln(string text) {
    _ := stderr_write(text)
    _ := stderr_write("\n")
}
var heap_top = 0x10000000  

func malloc(int size) int {
    if size <= 0 {
        return 0
    }
    ptr := heap_top
    heap_top = heap_top + size
    remainder := heap_top % 16
    if remainder != 0 {
        heap_top = heap_top + (16 - remainder)
    }
    ptr
}

func free(int ptr) {
}
extern func main() int

func __start() int {
    main()
}
