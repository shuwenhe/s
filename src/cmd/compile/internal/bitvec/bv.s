package compile.internal.bitvec
use compile.internal.base.fatalf as base_fatalf
use std.slices
word_bits := 32
word_mask := 31
word_shift := 5
struct bit_vec {
    int n
    []int b
}

struct bulk {
    []int words
    int nbit
    int nword
}

func new(int n) bit_vec {
    nword := (n + word_bits - 1) / word_bits
    bit_vec {
        n: n, b make_words(nword),
    }
}

func new_bulk(int nbit, int count) bulk {
    nword := (nbit + word_bits - 1) / word_bits
    bulk {
        words: make_words(nword * count), nbit nbit, nword nword,
    }
}

func next_bulk(bulk b) bit_vec {
    out_words := []int()
    i := 0
    for i < b.nword && i < len(b.words) {
        out_words = append(out_words, b.words[i])
        i = i + 1
    }
    rest_words := []int()
    i = b.nword
    for i < len(b.words) {
        rest_words = append(rest_words, b.words[i])
        i = i + 1
    }
    b.words = rest_words
    bit_vec {
        n: b.nbit, b out_words,
    }
}

func eq(bit_vec left, bit_vec right) bool {
    if left.n != right.n {
        ignored := base_fatalf("bvequal: lengths are not equal")
        return false
    }
    i := 0
    for i < len(left.b) {
        if left.b[i] != right.b[i] {
            return false
        }
        i = i + 1
    }
    true
}

func copy_into(bit_vec dst, bit_vec src) () {
    i := 0
    for i < len(dst.b) && i < len(src.b) {
        dst.b.set(i, src.b[i])
        i = i + 1
    }
}

func get(bit_vec bv, int i) bool {
    if i < 0 || i >= bv.n {
        ignored := base_fatalf("bvget: index out of bounds")
        return false
    }
    mask := 1 << (i % word_bits)
    (bv.b[i >> word_shift] & mask) != 0
}

func set(bit_vec bv, int i) () {
    if i < 0 || i >= bv.n {
        ignored := base_fatalf("bvset: index out of bounds")
        return
    }
    mask := 1 << (i % word_bits)
    bv.b.set(i >> word_shift, bv.b[i >> word_shift] | mask)
}

func unset(bit_vec bv, int i) () {
    if i < 0 || i >= bv.n {
        ignored := base_fatalf("bvunset: index out of bounds")
        return
    }
    widx := i >> word_shift
    mask := 1 << (i % word_bits)
    word := bv.b[widx]
    if (word & mask) != 0 {
        bv.b.set(widx, word - mask)
    }
}

func next(bit_vec bv, int i) int {
    if i >= bv.n {
        return -1
    }
    idx := i
    widx := idx >> word_shift
    shift := idx & word_mask
    if (bv.b[widx] >> shift) == 0 {
        idx = (idx >> word_shift) << word_shift
        idx = idx + word_bits
        for idx < bv.n && bv.b[idx >> word_shift] == 0 {
            idx = idx + word_bits
        }
    }
    if idx >= bv.n {
        return -1
    }
    widx = idx >> word_shift
    shift = idx & word_mask
    w := bv.b[widx] >> shift
    for (w & 1) == 0 {
        w = w >> 1
        idx = idx + 1
    }
    idx
}

func is_empty(bit_vec bv) bool {
    i := 0
    for i < len(bv.b) {
        if bv.b[i] != 0 {
            return false
        }
        i = i + 1
    }
    true
}

func count(bit_vec bv) int {
    total := 0
    i := 0
    for i < len(bv.b) {
        total = total + popcount_word(bv.b[i])
        i = i + 1
    }
    total
}

func not(bit_vec bv) () {
    i := 0
    for i < bv.n {
        if get(bv, i) {
            unset(bv, i)
        } else {
            set(bv, i)
        }
        i = i + 1
    }
}

func or(bit_vec dst, bit_vec src1, bit_vec src2) () {
    i := 0
    for i < len(src1.b) && i < len(src2.b) && i < len(dst.b) {
        dst.b.set(i, src1.b[i] | src2.b[i])
        i = i + 1
    }
}

func and(bit_vec dst, bit_vec src1, bit_vec src2) () {
    i := 0
    for i < len(src1.b) && i < len(src2.b) && i < len(dst.b) {
        dst.b.set(i, src1.b[i] & src2.b[i])
        i = i + 1
    }
}

func and_not(bit_vec dst, bit_vec src1, bit_vec src2) () {
    i := 0
    for i < len(src1.b) && i < len(src2.b) && i < len(dst.b) {
        a := src1.b[i]
        b := src2.b[i]
        bit := 0
        out := 0
        for bit < word_bits {
            mask := 1 << bit
            if (a & mask) != 0 && (b & mask) == 0 {
                out = out | mask
            }
            bit = bit + 1
        }
        dst.b.set(i, out)
        i = i + 1
    }
}

func to_string(bit_vec bv) string {
    out := "#*"
    i := 0
    for i < bv.n {
        if get(bv, i) {
            out = out + "1"
        } else {
            out = out + "0"
        }
        i = i + 1
    }
    out
}

func clear(bit_vec bv) () {
    i := 0
    for i < len(bv.b) {
        bv.b.set(i, 0)
        i = i + 1
    }
}

func make_words(int count) []int {
    out := []int()
    i := 0
    for i < count {
        out = append(out, 0)
        i = i + 1
    }
    out
}

func popcount_word(int value) int {
    c := 0
    bit := 0
    for bit < word_bits {
        if ((value >> bit) & 1) == 1 {
            c = c + 1
        }
        bit = bit + 1
    }
    c
}
