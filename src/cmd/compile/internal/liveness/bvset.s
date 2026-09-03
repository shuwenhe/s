package compile.internal.liveness
use std.slices
struct bv_set {
    []int[]] rows
}

func new_bv_set() bv_set {
    bv_set { rows: []int[]]() }
}

func bvset_add([]int[]] rows, []int bits) []int[]] {
    normalized := normalize_bits(bits)
    i := 0
    for i < len(rows) {
        if bitmap_equal(rows[i], normalized) {
            return rows
        }
        i = i + 1
    }
    rows = append(rows, normalized)
    rows
}

func bvset_extract_unique(bv_set set) []int[]] {
    set.rows
}

func normalize_bits([]int bits) []int {
    out := []int()
    i := 0
    for i < len(bits) {
        if bits[i] != 0 {
            out = append(out, 1)
        } else {
            out = append(out, 0)
        }
        i = i + 1
    }
    out
}

func bitmap_equal([]int left, []int right) bool {
    if len(left) != len(right) {
        return false
    }
    i := 0
    for i < len(left) {
        if left[i] != right[i] {
            return false
        }
        i = i + 1
    }
    true
}
