package compile.internal.ssa
use std.slices

struct int_tuple {
    int[] items
}

func make_tuple2(int first, int second) int_tuple {
    items := int[]()
    items = append(items, first)
    items = append(items, second)
    int_tuple { items: items }
}

func tuple_len(int_tuple t) int {
    len(t.items)
}

func tuple_at(int_tuple t, int idx) int {
    if idx < 0 || idx >= len(t.items) {
        return 0
    }
    t.items[idx]
}

func tuple_equal(int_tuple a, int_tuple b) bool {
    if len(a.items) != len(b.items) {
        return false
    }
    i := 0
    for i < len(a.items) {
        if a.items[i] != b.items[i] {
            return false
        }
        i = i + 1
    }
    true
}
