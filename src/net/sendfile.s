package src.net

use src.syscall as sc
use std.result.result

func send_file(int socket_fd, int file_fd, int offset, int count) result[int, net_error] {
    switch sc.sendfile(socket_fd, file_fd, offset, count) {
        result::ok(n) : result::ok(n),
        result::err(e) : result::err(wrap_sc_err(e)),
    }
}

func sendfile_unit_name() string { "src/net/sendfile" }
func sendfile_unit_ready() int { 1 }
