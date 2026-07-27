package compile.internal.ssa

struct int_pair {
    int left
    int right
}

func make_int_pair(int left, int right) int_pair {
    int_pair {
        left: left,
        right: right,
    }
}

func pair_swap(int_pair p) int_pair {
    int_pair {
        left: p.right,
        right: p.left,
    }
}

func pair_equal(int_pair a, int_pair b) bool {
    a.left == b.left && a.right == b.right
}

func pair_contains(int_pair p, int value) bool {
    p.left == value || p.right == value
}
