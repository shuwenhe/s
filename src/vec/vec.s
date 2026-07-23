package std.vec

use std.option.option
use std.prelude.box
use std.prelude.box

struct raw_vec[t] {
    box[array[t]] storage
    int capacity
}

struct vec[t] {
    raw_vec[t] raw
    int length
}

func new_vec[t]() vec[t] {
    with_capacity[t](4)
}

func with_capacity[t](int capacity) vec[t] {
    let initial =
        if capacity > 0 {
            capacity
        } else {
            4
        }
    vec[t] {
        raw: raw_vec[t] {
            storage: box(new_array[t](initial)),
            capacity: initial,
        },
        length: 0,
    }
}

func (self: &mut vec[t]) push(t value) () {
        ensure_capacity(self, self.length + 1)
        array_set(self.raw.storage.value, self.length, value)
        self.length = self.length + 1
    }

func (self: &mut vec[t]) pop() option[t] {
        if self.length == 0 {
            return option::none
        }
        self.length = self.length - 1
        option::some(array_get(self.raw.storage.value, self.length))
    }

func (self: vec[t]) len() int {
        self.length
    }

func (self: vec[t]) capacity() int {
        self.raw.capacity
    }

func (self: vec[t]) is_empty() bool {
        self.length == 0
    }

func (self: vec[t]) get(int index) option[t] {
        if index < 0 || index >= self.length {
            return option::none
        }
        option::some(array_get(self.raw.storage.value, index))
    }

func (self: &mut vec[t]) set(int index, t value) bool {
        if index < 0 || index >= self.length {
            return false
        }
        array_set(self.raw.storage.value, index, value)
        true
    }

func (self: &mut vec[t]) clear() () {
        self.length = 0
    }

func ensure_capacity[t](vec[t] mut vec, int wanted) () {
    if wanted <= vec.raw.capacity {
        return
    }

    let next = grow_capacity(vec.raw.capacity, wanted)
    let next_storage = new_array[t](next)
    let i = 0
    while i < vec.length {
        array_set(next_storage, i, array_get(vec.raw.storage.value, i))
        i = i + 1
    }
    vec.raw.storage = box(next_storage)
    vec.raw.capacity = next
}

func grow_capacity(int current, int wanted) int {
    let next = current
    if next <= 0 {
        next = 4
    }
    while next < wanted {
        next = next * 2
    }
    next
}

struct array[t] {}

func new_array[t](int size) array[t] {
    __vec_new_array[t](size)
}

func array_get[t](array[t] array, int index) t {
    __vec_array_get[t](array, index)
}

func array_set[t](array[t] array, int index, t value) () {
    __vec_array_set[t](array, index, value)
}

extern "intrinsic" func __vec_new_array[t](int size) array[t]

extern "intrinsic" func __vec_array_get[t](array[t] array, int index) t

extern "intrinsic" func __vec_array_set[t](array[t] array, int index, t value) ()
