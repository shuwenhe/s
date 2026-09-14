package src.net
import (
    "std.result"
)
func send_file(int socket_fd, int file_fd, int offset, int count) (int, net_error) {
    switch sc.sendfile(socket_fd, file_fd, offset, count) {
        n : n,
        e : wrap_sc_err(e),
    }
}
