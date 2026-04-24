package compile.internal.ssa

use std.vec.vec

struct int_tuple {
    vec[int] items
}

func make_tuple2(int first, int second) int_tuple {
    var items = vec[int]()
    items.push(first)
    items.push(second)
    int_tuple { items: items }
}

func tuple_len(int_tuple t) int {
    t.items.len()
}

func tuple_at(int_tuple t, int idx) int {
    if idx < 0 || idx >= t.items.len() {
        return 0
    }
    t.items[idx]
}

func tuple_equal(int_tuple a, int_tuple b) bool {
    if a.items.len() != b.items.len() {
        return false
    }
    var i = 0
    while i < a.items.len() {
        if a.items[i] != b.items[i] {
            return false
        }
        i = i + 1
    }
    true
}
