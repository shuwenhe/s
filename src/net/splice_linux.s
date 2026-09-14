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
