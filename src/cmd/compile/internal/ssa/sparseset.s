package compile.internal.ssa

use std.vec.vec

struct sparse_set {
    vec[int] dense
    vec[int] sparse
}

func new_sparse_set(int n) sparse_set {
    var sparse = vec[int]()
    var i = 0
    while i < n {
        sparse.push(0)
        i = i + 1
    }
    sparse_set {
        dense: vec[int](),
        sparse: sparse,
    }
}

func sparse_set_cap(sparse_set s) int {
    s.sparse.len()
}

func sparse_set_size(sparse_set s) int {
    s.dense.len()
}

func sparse_set_contains(sparse_set s, int x) bool {
    if x < 0 || x >= s.sparse.len() {
        return false
    }
    var i = s.sparse[x]
    i < s.dense.len() && s.dense[i] == x
}

func sparse_set_add(mut sparse_set s, int x) sparse_set {
    if x < 0 || x >= s.sparse.len() {
        return s
    }
    var i = s.sparse[x]
    if i < s.dense.len() && s.dense[i] == x {
        return s
    }
    s.dense.push(x)
    s.sparse[x] = s.dense.len() - 1
    s
}

func sparse_set_remove(mut sparse_set s, int x) sparse_set {
    if x < 0 || x >= s.sparse.len() {
        return s
    }
    var i = s.sparse[x]
    if i < s.dense.len() && s.dense[i] == x {
        var last = s.dense[s.dense.len() - 1]
        s.dense[i] = last
        s.sparse[last] = i
        s.dense.pop()
    }
    s
}

func sparse_set_pop(mut sparse_set s) int_pair {
    if s.dense.len() == 0 {
        return make_int_pair(0, 0)
    }
    var x = s.dense[s.dense.len() - 1]
    s.dense.pop()
    make_int_pair(x, 1)
}

func sparse_set_clear(mut sparse_set s) sparse_set {
    s.dense = vec[int]()
    s
}
