package std.vec

use std.option.Option
use std.prelude.Box
use std.prelude.box

struct RawVec[T] {
    Box[Array[T]] storage,
    int32 capacity,
}

struct Vec[T] {
    RawVec[T] raw,
    int32 length,
}

func newVec[T]() Vec[T] {
    withCapacity[T](4)
}

func withCapacity[T](int32 capacity) Vec[T] {
    var initial =
        if capacity > 0 {
            capacity
        } else {
            4
        }
    Vec[T] {
        raw: RawVec[T] {
            storage: box(newArray[T](initial)),
            capacity: initial,
        },
        length: 0,
    }
}

impl Vec[T] {
    func push(mut self, T value) () {
        ensureCapacity(self, self.length + 1)
        arraySet(self.raw.storage.value, self.length, value)
        self.length = self.length + 1
    }

    func pop(mut self) Option[T] {
        if self.length == 0 {
            return Option::None
        }
        self.length = self.length - 1
        Option::Some(arrayGet(self.raw.storage.value, self.length))
    }

    func len(self) int32 {
        self.length
    }

    func capacity(self) int32 {
        self.raw.capacity
    }

    func isEmpty(self) bool {
        self.length == 0
    }

    func get(self, int32 index) Option[T] {
        if index < 0 || index >= self.length {
            return Option::None
        }
        Option::Some(arrayGet(self.raw.storage.value, index))
    }

    func set(mut self, int32 index, T value) bool {
        if index < 0 || index >= self.length {
            return false
        }
        arraySet(self.raw.storage.value, index, value)
        true
    }

    func clear(mut self) () {
        self.length = 0
    }
}

func ensureCapacity[T](Vec[T] mut vec, int32 wanted) () {
    if wanted <= vec.raw.capacity {
        return
    }

    var next = growCapacity(vec.raw.capacity, wanted)
    var nextStorage = newArray[T](next)
    var i = 0
    while i < vec.length {
        arraySet(nextStorage, i, arrayGet(vec.raw.storage.value, i))
        i = i + 1
    }
    vec.raw.storage = box(nextStorage)
    vec.raw.capacity = next
}

func growCapacity(int32 current, int32 wanted) int32 {
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

func newArray[T](int32 size) Array[T] {
    __vec_new_array[T](size)
}

func arrayGet[T](Array[T] array, int32 index) T {
    __vec_array_get[T](array, index)
}

func arraySet[T](Array[T] array, int32 index, T value) () {
    __vec_array_set[T](array, index, value)
}

extern "intrinsic" func __vec_new_array[T](int32 size) Array[T]

extern "intrinsic" func __vec_array_get[T](Array[T] array, int32 index) T

extern "intrinsic" func __vec_array_set[T](Array[T] array, int32 index, T value) ()
