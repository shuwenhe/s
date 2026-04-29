package compile.internal.ssa

use std.vec.vec

struct sparse_entry {
    int key
    int value
}

struct sparse_map {
    vec[sparse_entry] dense
    vec[int] sparse
}

func new_sparse_map(int n) sparse_map {
    let sparse = vec[int]()
    let i = 0
    while i < n {
        sparse.push(0)
        i = i + 1
    }
    sparse_map {
        dense: vec[sparse_entry](),
        sparse: sparse,
    }
}

func sparse_map_contains(sparse_map s, int key) bool {
    if key < 0 || key >= s.sparse.len() {
        return false
    }
    let i = s.sparse[key]
    i < s.dense.len() && s.dense[i].key == key
}

func sparse_map_get(sparse_map s, int key) int_pair {
    if key < 0 || key >= s.sparse.len() {
        return make_int_pair(0, 0)
    }
    let i = s.sparse[key]
    if i < s.dense.len() && s.dense[i].key == key {
        return make_int_pair(s.dense[i].value, 1)
    }
    make_int_pair(0, 0)
}

func sparse_map_set(mut sparse_map s, int key, int value) sparse_map {
    if key < 0 || key >= s.sparse.len() {
        return s
    }
    let i = s.sparse[key]
    if i < s.dense.len() && s.dense[i].key == key {
        s.dense[i].value = value
        return s
    }
    s.dense.push(sparse_entry { key: key, value: value })
    s.sparse[key] = s.dense.len() - 1
    s
}

func sparse_map_remove(mut sparse_map s, int key) sparse_map {
    if key < 0 || key >= s.sparse.len() {
        return s
    }
    let i = s.sparse[key]
    if i < s.dense.len() && s.dense[i].key == key {
        let last = s.dense[s.dense.len() - 1]
        s.dense[i] = last
        s.sparse[last.key] = i
        s.dense.pop()
    }
    s
}

func sparse_map_clear(mut sparse_map s) sparse_map {
    s.dense = vec[sparse_entry]()
    s
}
