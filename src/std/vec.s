package std.vec

use std.option.Option
use std.prelude.Box
use std.prelude.box

struct RawVec[T] {
    Box[Array[T]] storage,
    i32 capacity,
}

struct Vec[T] {
    RawVec[T] raw,
    i32 length,
}

func new_vec[T]() -> Vec[T] {
    with_capacity[T](4)
}

func with_capacity[T](i32 capacity) -> Vec[T] {
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
    func push(mut self, T value) -> () {
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

    func get(self, i32 index) -> Option[T] {
        if index < 0 || index >= self.length {
            return Option::None
        }
        Option::Some(array_get(self.raw.storage.value, index))
    }

    func set(mut self, i32 index, T value) -> bool {
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

func ensure_capacity[T](Vec[T] mut vec, i32 wanted) -> () {
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

func grow_capacity(i32 current, i32 wanted) -> i32 {
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

func new_array[T](i32 size) -> Array[T] {
    __vec_new_array[T](size)
}

func array_get[T](Array[T] array, i32 index) -> T {
    __vec_array_get[T](array, index)
}

func array_set[T](Array[T] array, i32 index, T value) -> () {
    __vec_array_set[T](array, index, value)
}

extern "intrinsic" func __vec_new_array[T](i32 size) -> Array[T]

extern "intrinsic" func __vec_array_get[T](Array[T] array, i32 index) -> T

extern "intrinsic" func __vec_array_set[T](Array[T] array, i32 index, T value) -> ()
