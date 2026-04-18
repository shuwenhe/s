package demo.core

use std.io.Reader
use std.result.Result as Res

struct Config[T] {
    string Addr,
    int32 retries,
}

enum Option[T] {
    Some(T),
    None,
}

trait reader_like[T] {
    func read(&mut Self self, []u8 buf) Result[usize, io_error];
}

func load[T: Reader](T reader, string path) Result[string, io_error] {
    var value = 1
    value
}

impl reader_like[File] for File {
    func read(&mut Self self, []u8 buf) Result[usize, io_error] {
        buf
    }
}
