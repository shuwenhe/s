package std.vec

use std.option.option
use std.prelude.box
use std.prelude.box

struct raw_vec[t] {
    box[array[t]] storage
    int32 capacity
}

struct vec[t] {
    raw_vec[t] raw
    int32 length
}

func new_vec[t]() vec[t] {
    with_capacity[t](4)
}

func with_capacity[t](int32 capacity) vec[t] {
    var initial =
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

impl vec[t] {
    func push(mut self, t value) () {
        ensure_capacity(self, self.length + 1)
        array_set(self.raw.storage.value, self.length, value)
        self.length = self.length + 1
    }

    func pop(mut self) option[t] {
        if self.length == 0 {
            return option::none
        }
        self.length = self.length - 1
        option::some(array_get(self.raw.storage.value, self.length))
    }

    func len(self) int32 {
        self.length
    }

    func capacity(self) int32 {
        self.raw.capacity
    }

    func is_empty(self) bool {
        self.length == 0
    }

    func get(self, int32 index) option[t] {
        if index < 0 || index >= self.length {
            return option::none
        }
        option::some(array_get(self.raw.storage.value, index))
    }

    func set(mut self, int32 index, t value) bool {
        if index < 0 || index >= self.length {
            return false
        }
        array_set(self.raw.storage.value, index, value)
        true
    }

    func clear(mut self) () {
        self.length = 0
    }
}

func ensure_capacity[t](vec[t] mut vec, int32 wanted) () {
    if wanted <= vec.raw.capacity {
        return
    }

    var next = grow_capacity(vec.raw.capacity, wanted)
    var next_storage = new_array[t](next)
    var i = 0
    while i < vec.length {
        array_set(next_storage, i, array_get(vec.raw.storage.value, i))
        i = i + 1
    }
    vec.raw.storage = box(next_storage)
    vec.raw.capacity = next
}

func grow_capacity(int32 current, int32 wanted) int32 {
    var next = current
    if next <= 0 {
        next = 4
    }
    while next < wanted {
        next = next * 2
    }
    next
}

struct array[t] {}

func new_array[t](int32 size) array[t] {
    __vec_new_array[t](size)
}

func array_get[t](array[t] array, int32 index) t {
    __vec_array_get[t](array, index)
}

func array_set[t](array[t] array, int32 index, t value) () {
    __vec_array_set[t](array, index, value)
}

extern "intrinsic" func __vec_new_array[t](int32 size) array[t]

extern "intrinsic" func __vec_array_get[t](array[t] array, int32 index) t

extern "intrinsic" func __vec_array_set[t](array[t] array, int32 index, t value) ()
