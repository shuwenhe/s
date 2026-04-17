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

trait ReaderLike[T] {
    func read(&mut Self self, []u8 buf) Result[usize, IoError];
}

func load[T: Reader](T reader, string path) Result[string, IoError] {
    var value = 1
    value
}

impl ReaderLike[File] for File {
    func read(&mut Self self, []u8 buf) Result[usize, IoError] {
        buf
    }
}
