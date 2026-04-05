package std.vec

use std.option.Option
use std.prelude.Box
use std.prelude.box

pub struct RawVec[T] {
    storage: Box[Array[T]],
    capacity: i32,
}

pub struct Vec[T] {
    raw: RawVec[T],
    length: i32,
}

pub fn new_vec[T]() -> Vec[T] {
    Vec[T] {
        raw: RawVec[T] {
            storage: box(new_array[T](4)),
            capacity: 4,
        },
        length: 0,
    }
}

impl Vec[T] {
    pub fn push(mut self, value: T) -> () {
        ensure_capacity(self, self.length + 1)
        array_set(self.raw.storage.value, self.length, value)
        self.length = self.length + 1
    }

    pub fn pop(mut self) -> Option[T] {
        if self.length == 0 {
            return Option::None
        }
        self.length = self.length - 1
        Option::Some(array_get(self.raw.storage.value, self.length))
    }

    pub fn len(self) -> i32 {
        self.length
    }
}

pub fn ensure_capacity[T](mut vec: Vec[T], wanted: i32) -> () {
    if wanted <= vec.raw.capacity {
        return
    }

    let next = grow_capacity(vec.raw.capacity, wanted)
    let next_storage = new_array[T](next)
    let i = 0
    while i < vec.length {
        array_set(next_storage, i, array_get(vec.raw.storage.value, i))
        i = i + 1
    }
    vec.raw.storage = box(next_storage)
    vec.raw.capacity = next
}

pub fn grow_capacity(current: i32, wanted: i32) -> i32 {
    let next = current
    if next <= 0 {
        next = 4
    }
    while next < wanted {
        next = next * 2
    }
    next
}

pub struct Array[T] {}

pub fn new_array[T](size: i32) -> Array[T] {
    __vec_new_array[T](size)
}

pub fn array_get[T](array: Array[T], index: i32) -> T {
    __vec_array_get[T](array, index)
}

pub fn array_set[T](array: Array[T], index: i32, value: T) -> () {
    __vec_array_set[T](array, index, value)
}

extern "intrinsic" fn __vec_new_array[T](size: i32) -> Array[T]

extern "intrinsic" fn __vec_array_get[T](array: Array[T], index: i32) -> T

extern "intrinsic" fn __vec_array_set[T](array: Array[T], index: i32, value: T) -> ()
