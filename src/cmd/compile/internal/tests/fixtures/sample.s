package demo.core
use std.io.reader
use std.result.result as res

struct config[t] {
    string addr
    int retries
}

enum option[t] {
    some(t),
    none,
}
trait reader_like[t] {
    func read([]u8 buf) (usize, io_error);
}

func load[t: reader](t reader, string path) (string, io_error) {
    value := 1
    value
}

func (file* self) read([]u8 buf) (usize, io_error) {
    buf
}
