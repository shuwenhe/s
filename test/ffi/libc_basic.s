extern "libc:strlen" func c_strlen(string text) int
extern "libc:socket" func c_socket(int domain, int kind, int protocol) int
extern "libc:close" func c_close(int fd) int

func main() int {
    if c_strlen("native ffi") != 10 {
        return 1
    }
    let fd = c_socket(2, 1, 6)
    if fd < 0 {
        return 2
    }
    if c_close(fd) < 0 {
        return 3
    }
    0
}
