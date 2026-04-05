package std.vec

use std.option.Option
use std.prelude.Box
use std.prelude.box

struct RawVec[T] {
    storage: Box[Array[T]],
    capacity: i32,
}

struct Vec[T] {
    raw: RawVec[T],
    length: i32,
}

func new_vec[T]() -> Vec[T] {
    with_capacity[T](4)
}

func with_capacity[T](capacity: i32) -> Vec[T] {
    var initial =
        if capacity > 0 {
            capacity
        } else {
            4
        }
    Vec[T] {
        raw: RawVec[T] {
            storage: box(new_array[T](initial)),
            capacity: initial,
        },
        length: 0,
    }
}

impl Vec[T] {
    func push(mut self, value: T) -> () {
        ensure_capacity(self, self.length + 1)
        array_set(self.raw.storage.value, self.length, value)
        self.length = self.length + 1
    }

    func pop(mut self) -> Option[T] {
        if self.length == 0 {
            return Option::None
        }
        self.length = self.length - 1
        Option::Some(array_get(self.raw.storage.value, self.length))
    }

    func len(self) -> i32 {
        self.length
    }

    func capacity(self) -> i32 {
        self.raw.capacity
    }

    func is_empty(self) -> bool {
        self.length == 0
    }

    func get(self, index: i32) -> Option[T] {
        if index < 0 || index >= self.length {
            return Option::None
        }
        Option::Some(array_get(self.raw.storage.value, index))
    }

    func set(mut self, index: i32, value: T) -> bool {
        if index < 0 || index >= self.length {
            return false
        }
        array_set(self.raw.storage.value, index, value)
        true
    }

    func clear(mut self) -> () {
        self.length = 0
    }
}

func ensure_capacity[T](mut vec: Vec[T], wanted: i32) -> () {
    if wanted <= vec.raw.capacity {
        return
    }

    var next = grow_capacity(vec.raw.capacity, wanted)
    var next_storage = new_array[T](next)
    var i = 0
    while i < vec.length {
        array_set(next_storage, i, array_get(vec.raw.storage.value, i))
        i = i + 1
    }
    vec.raw.storage = box(next_storage)
    vec.raw.capacity = next
}

func grow_capacity(current: i32, wanted: i32) -> i32 {
    var next = current
    if next <= 0 {
        next = 4
    }
    while next < wanted {
        next = next * 2
    }
    next
}

struct Array[T] {}

func new_array[T](size: i32) -> Array[T] {
    __vec_new_array[T](size)
}

func array_get[T](array: Array[T], index: i32) -> T {
    __vec_array_get[T](array, index)
}

func array_set[T](array: Array[T], index: i32, value: T) -> () {
    __vec_array_set[T](array, index, value)
}

extern "intrinsic" func __vec_new_array[T](size: i32) -> Array[T]

extern "intrinsic" func __vec_array_get[T](array: Array[T], index: i32) -> T

extern "intrinsic" func __vec_array_set[T](array: Array[T], index: i32, value: T) -> ()
