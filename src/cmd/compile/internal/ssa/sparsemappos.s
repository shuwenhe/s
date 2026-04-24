package compile.internal.ssa

struct sparse_pos_entry {
    int pos
    int value
}

func make_sparse_pos_entry(int pos, int value) sparse_pos_entry {
    sparse_pos_entry {
        pos: pos,
        value: value,
    }
}

func sparse_pos_get(sparse_map s, int pos) int_pair {
    sparse_map_get(s, pos)
}

func sparse_pos_set(mut sparse_map s, int pos, int value) sparse_map {
    sparse_map_set(s, pos, value)
}
