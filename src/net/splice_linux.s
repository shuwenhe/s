package src.net

use src.syscall as sc
use std.result.result

func splice_file(int input_fd, int output_fd, int count) result[int, net_error] {
    switch sc.splice(input_fd, output_fd, count) {
        result::ok(n) : result::ok(n),
        result::err(e) : result::err(wrap_sc_err(e)),
    }
}

func splice_linux_unit_name() string { "src/net/splice_linux" }
func splice_linux_unit_ready() int { 1 }
