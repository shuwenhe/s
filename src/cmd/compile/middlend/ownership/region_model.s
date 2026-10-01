package ownership_region_model

func ownership_region_bit_set(int bits, int bit) bool {
    value := bits / bit
    while value >= 2 {
        value = value - 2
    }
    return value == 1
}

func ownership_region_add_point(int bits, int point) int {
    bit := 1
    i := 0
    while i < point {
        bit = bit * 2
        i = i + 1
    }
    if ownership_region_bit_set(bits, bit) { return bits }
    return bits + bit
}

func ownership_region_union(int target_bits, int source_bits) int {
    result := target_bits
    point := 0
    bit := 1
    while point < 8 {
        if ownership_region_bit_set(source_bits, bit) {
            if !ownership_region_bit_set(result, bit) { result = result + bit }
        }
        bit = bit * 2
        point = point + 1
    }
    return result
}

func ownership_region_covers_point(int bits, int point) bool {
    before := false
    after := false
    i := 0
    bit := 1
    while i < 8 {
        if ownership_region_bit_set(bits, bit) {
            if i <= point { before = true }
            if i >= point { after = true }
        }
        bit = bit * 2
        i = i + 1
    }
    return before && after
}

func ownership_region_model_verify() int {
    a := ownership_region_add_point(0, 0)
    a = ownership_region_add_point(a, 3)
    b := ownership_region_add_point(0, 5)
    u := ownership_region_union(a, b)
    if !ownership_region_bit_set(u, 1) { return 1 }
    if !ownership_region_bit_set(u, 8) { return 2 }
    if !ownership_region_bit_set(u, 32) { return 3 }
    if !ownership_region_covers_point(u, 4) { return 4 }
    if ownership_region_covers_point(a, 5) { return 5 }
    return 0
}
