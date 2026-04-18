package demo.core

use std.io.reader
use std.result.result as res

struct config[t] {
    string addr,
    int32 retries,
}

enum option[t] {
    some(t),
    none,
}

trait reader_like[t] {
    func read(&mut self self, []u8 buf) result[usize, io_error];
}

func load[t: reader](t reader, string path) result[string, io_error] {
    var value = 1
    value
}

impl reader_like[file] for file {
    func read(&mut self self, []u8 buf) result[usize, io_error] {
        buf
    }
}
