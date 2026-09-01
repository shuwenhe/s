package compile.internal.ssa
use std.slices
struct sparse_entry {
    int key
    int value
}

struct sparse_map {
    sparse_entry[] dense
    int[] sparse
}

func new_sparse_map(int n) sparse_map {
    sparse := int[]()
    i := 0
    for i < n {
        sparse = append(sparse, 0)
        i = i + 1
    }
    sparse_map {
        dense: sparse_entry[](),
        sparse: sparse,
    }
}

func sparse_map_contains(sparse_map s, int key) bool {
    if key < 0 || key >= len(s.sparse) {
        return false
    }
    i := s.sparse[key]
    i < len(s.dense) && s.dense[i].key == key
}

func sparse_map_get(sparse_map s, int key) int_pair {
    if key < 0 || key >= len(s.sparse) {
        return make_int_pair(0, 0
    }
    i := s.sparse[key]
    if i < len(s.dense) && s.dense[i].key == key {
        return make_int_pair(s.dense[i].value, 1
    }
    make_int_pair(0, 0)
}

func sparse_map_set(sparse_map s, int key, int value) sparse_map {
    if key < 0 || key >= len(s.sparse) {
        return s
    }
    i := s.sparse[key]
    if i < len(s.dense) && s.dense[i].key == key {
        s.dense[i].value = value
        return s
    }
    s.dense = append(s.dense, sparse_entry { key: key, value: value })
    s.sparse[key] = len(s.dense) - 1
    s
}

func sparse_map_remove(sparse_map s, int key) sparse_map {
    if key < 0 || key >= len(s.sparse) {
        return s
    }
    i := s.sparse[key]
    if i < len(s.dense) && s.dense[i].key == key {
        last := s.dense[len(s.dense) - 1]
        s.dense[i] = last
        s.sparse[last.key] = i
        s.dense.pop()
    }
    s
}

func sparse_map_clear(sparse_map s) sparse_map {
    s.dense = sparse_entry[]()
    s
}
