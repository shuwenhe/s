package src.net
import (
    "std.result"
)
func splice_file(int input_fd, int output_fd, int count) (int, net_error) {
    switch sc.splice(input_fd, output_fd, count) {
        n : n,
        e : wrap_sc_err(e),
    }
}

func splice_linux_unit_name() string { "src/net/splice_linux" }

func splice_linux_unit_ready() int { 1 }
