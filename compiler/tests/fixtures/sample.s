package demo.core

use std.io.Reader
use std.result.Result as Res

struct Config[T] {
    String Addr,
    i32 retries,
}

enum Option[T] {
    Some(T),
    None,
}

trait ReaderLike[T] {
    Result[usize, IoError] read(&mut Self self, []u8 buf);
}

Result[String, IoError] load[T: Reader](T reader, String path){
    var value = 1
    value
}

impl ReaderLike[File] for File {
    Result[usize, IoError] read(&mut Self self, []u8 buf){
        buf
    }
}
