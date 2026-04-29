package compile.internal.bitvec

use compile.internal.base.fatalf as base_fatalf
use std.vec.vec

let word_bits = 32
let word_mask = 31
let word_shift = 5

struct bit_vec {
    int n
    vec[int] b
}

struct bulk {
    vec[int] words
    int nbit
    int nword
}

func new(int n) bit_vec {
    let nword = (n + word_bits - 1) / word_bits
    bit_vec {
        n: n,
        b: make_words(nword),
    }
}

func new_bulk(int nbit, int count) bulk {
    let nword = (nbit + word_bits - 1) / word_bits
    bulk {
        words: make_words(nword * count),
        nbit: nbit,
        nword: nword,
    }
}

func next_bulk(bulk mut b) bit_vec {
    let out_words = vec[int]()
    let i = 0
    while i < b.nword && i < b.words.len() {
        out_words.push(b.words[i])
        i = i + 1
    }

    let rest_words = vec[int]()
    i = b.nword
    while i < b.words.len() {
        rest_words.push(b.words[i])
        i = i + 1
    }

    b.words = rest_words

    bit_vec {
        n: b.nbit,
        b: out_words,
    }
}

func eq(bit_vec left, bit_vec right) bool {
    if left.n != right.n {
        let ignored = base_fatalf("bvequal: lengths are not equal")
        return false
    }
    let i = 0
    while i < left.b.len() {
        if left.b[i] != right.b[i] {
            return false
        }
        i = i + 1
    }
    true
}

func copy_into(bit_vec mut dst, bit_vec src) () {
    let i = 0
    while i < dst.b.len() && i < src.b.len() {
        dst.b.set(i, src.b[i])
        i = i + 1
    }
}

func get(bit_vec bv, int i) bool {
    if i < 0 || i >= bv.n {
        let ignored = base_fatalf("bvget: index out of bounds")
        return false
    }
    let mask = 1 << (i % word_bits)
    (bv.b[i >> word_shift] & mask) != 0
}

func set(bit_vec mut bv, int i) () {
    if i < 0 || i >= bv.n {
        let ignored = base_fatalf("bvset: index out of bounds")
        return
    }
    let mask = 1 << (i % word_bits)
    bv.b.set(i >> word_shift, bv.b[i >> word_shift] | mask)
}

func unset(bit_vec mut bv, int i) () {
    if i < 0 || i >= bv.n {
        let ignored = base_fatalf("bvunset: index out of bounds")
        return
    }
    let widx = i >> word_shift
    let mask = 1 << (i % word_bits)
    let word = bv.b[widx]
    if (word & mask) != 0 {
        bv.b.set(widx, word - mask)
    }
}

func next(bit_vec bv, int i) int {
    if i >= bv.n {
        return -1
    }

    let idx = i
    let widx = idx >> word_shift
    let shift = idx & word_mask
    if (bv.b[widx] >> shift) == 0 {
        idx = (idx >> word_shift) << word_shift
        idx = idx + word_bits
        while idx < bv.n && bv.b[idx >> word_shift] == 0 {
            idx = idx + word_bits
        }
    }

    if idx >= bv.n {
        return -1
    }

    widx = idx >> word_shift
    shift = idx & word_mask
    let w = bv.b[widx] >> shift
    while (w & 1) == 0 {
        w = w >> 1
        idx = idx + 1
    }
    idx
}

func is_empty(bit_vec bv) bool {
    let i = 0
    while i < bv.b.len() {
        if bv.b[i] != 0 {
            return false
        }
        i = i + 1
    }
    true
}

func count(bit_vec bv) int {
    let total = 0
    let i = 0
    while i < bv.b.len() {
        total = total + popcount_word(bv.b[i])
        i = i + 1
    }
    total
}

func not(bit_vec mut bv) () {
    let i = 0
    while i < bv.n {
        if get(bv, i) {
            unset(bv, i)
        } else {
            set(bv, i)
        }
        i = i + 1
    }
}

func or(bit_vec mut dst, bit_vec src1, bit_vec src2) () {
    let i = 0
    while i < src1.b.len() && i < src2.b.len() && i < dst.b.len() {
        dst.b.set(i, src1.b[i] | src2.b[i])
        i = i + 1
    }
}

func and(bit_vec mut dst, bit_vec src1, bit_vec src2) () {
    let i = 0
    while i < src1.b.len() && i < src2.b.len() && i < dst.b.len() {
        dst.b.set(i, src1.b[i] & src2.b[i])
        i = i + 1
    }
}

func and_not(bit_vec mut dst, bit_vec src1, bit_vec src2) () {
    let i = 0
    while i < src1.b.len() && i < src2.b.len() && i < dst.b.len() {
        let a = src1.b[i]
        let b = src2.b[i]
        let bit = 0
        let out = 0
        while bit < word_bits {
            let mask = 1 << bit
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
    let out = "#*"
    let i = 0
    while i < bv.n {
        if get(bv, i) {
            out = out + "1"
        } else {
            out = out + "0"
        }
        i = i + 1
    }
    out
}

func clear(bit_vec mut bv) () {
    let i = 0
    while i < bv.b.len() {
        bv.b.set(i, 0)
        i = i + 1
    }
}

func make_words(int count) vec[int] {
    let out = vec[int]()
    let i = 0
    while i < count {
        out.push(0)
        i = i + 1
    }
    out
}

func popcount_word(int value) int {
    let c = 0
    let bit = 0
    while bit < word_bits {
        if ((value >> bit) & 1) == 1 {
            c = c + 1
        }
        bit = bit + 1
    }
    c
}
