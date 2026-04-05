package std.vec

use std.option.Option

pub struct Vec[T] {}

impl Vec[T] {
    pub fn push(mut self, value: T) -> () {}

    pub fn pop(mut self) -> Option[T] {
        Option::None
    }
}
