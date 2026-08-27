package compile.internal.ssa
use std.slices

struct sparse_set {
    int[] dense
    int[] sparse
}

func new_sparse_set(int n) sparse_set {
    sparse := int[]()
    i := 0
    for i < n {
        sparse = append(sparse, 0)
        i = i + 1
    }
    sparse_set {
        dense: int[](),
        sparse: sparse,
    }
}

func sparse_set_cap(sparse_set s) int {
    len(s.sparse)
}

func sparse_set_size(sparse_set s) int {
    len(s.dense)
}

func sparse_set_contains(sparse_set s, int x) bool {
    if x < 0 || x >= len(s.sparse) {
        return false
    }
    i := s.sparse[x]
    i < len(s.dense) && s.dense[i] == x
}

func sparse_set_add(sparse_set s, int x) sparse_set {
    if x < 0 || x >= len(s.sparse) {
        return s
    }
    i := s.sparse[x]
    if i < len(s.dense) && s.dense[i] == x {
        return s
    }
    s.dense = append(s.dense, x)
    s.sparse[x] = len(s.dense) - 1
    s
}

func sparse_set_remove(sparse_set s, int x) sparse_set {
    if x < 0 || x >= len(s.sparse) {
        return s
    }
    i := s.sparse[x]
    if i < len(s.dense) && s.dense[i] == x {
        last := s.dense[len(s.dense) - 1]
        s.dense[i] = last
        s.sparse[last] = i
        s.dense.pop()
    }
    s
}

func sparse_set_pop(sparse_set s) int_pair {
    if len(s.dense) == 0 {
        return make_int_pair(0, 0
    }
    x := s.dense[len(s.dense) - 1]
    s.dense.pop()
    make_int_pair(x, 1)
}

func sparse_set_clear(sparse_set s) sparse_set {
    s.dense = int[]()
    s
}
