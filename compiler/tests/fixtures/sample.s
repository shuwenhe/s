package demo.core

use std.io.Reader
use std.result.Result as Res

pub struct Config[T] {
    pub addr: String,
    retries: i32,
}

enum Option[T] {
    Some(T),
    None,
}

pub trait ReaderLike[T] {
    fn read(self: &mut Self, buf: []u8) -> Result[usize, IoError];
}

pub fn load[T: Reader](reader: T, path: String) -> Result[String, IoError] {
    let value = 1
    value
}

impl ReaderLike[File] for File {
    fn read(self: &mut Self, buf: []u8) -> Result[usize, IoError] {
        buf
    }
}
