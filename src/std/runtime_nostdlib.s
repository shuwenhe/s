package std.runtime_nostdlib
extern "intrinsic" func syscall_6(int nr, int a1, int a2, int a3, int a4, int a5, int a6) int
extern "intrinsic" func syscall_1(int nr, int a1) int
const sys_exit = 60
const sys_write = 1
const sys_read = 0
const sys_open = 2
const sys_close = 3
const sys_brk = 12
const stdin_fd = 0
const stdout_fd = 1
const stderr_fd = 2
func exit(int code) {
    _ := syscall_1(sys_exit, code)
}

func write_to_fd(int fd, string text) int {
    count := len(text)
    if count == 0 {
        return 0
    }
    syscall_6(sys_write, fd, 0, count, 0, 0, 0)
}

func stdout_write(string text) int {
    write_to_fd(stdout_fd, text)
}

func stderr_write(string text) int {
    write_to_fd(stderr_fd, text)
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
    heap_top = (heap_top + 15) & -16
    ptr
}

func free(int ptr) {
}
extern func main() int

func __start() int {
    main()
}
