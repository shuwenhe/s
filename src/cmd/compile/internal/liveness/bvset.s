package compile.internal.liveness

use std.vec.vec

struct bv_set {
    vec[vec[int]] rows
}

func new_bv_set() bv_set {
    bv_set { rows: vec[vec[int]]() }
}

func bvset_add(vec[vec[int]] rows, vec[int] bits) vec[vec[int]] {
    var normalized = normalize_bits(bits)
    var i = 0
    while i < rows.len() {
        if bitmap_equal(rows[i], normalized) {
            return rows
        }
        i = i + 1
    }
    rows.push(normalized)
    rows
}

func bvset_extract_unique(bv_set set) vec[vec[int]] {
    set.rows
}

func normalize_bits(vec[int] bits) vec[int] {
    var out = vec[int]()
    var i = 0
    while i < bits.len() {
        if bits[i] != 0 {
            out.push(1)
        } else {
            out.push(0)
        }
        i = i + 1
    }
    out
}

func bitmap_equal(vec[int] left, vec[int] right) bool {
    if left.len() != right.len() {
        return false
    }
    var i = 0
    while i < left.len() {
        if left[i] != right[i] {
            return false
        }
        i = i + 1
    }
    true
}
