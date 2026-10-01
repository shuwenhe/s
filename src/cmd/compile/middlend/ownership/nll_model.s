package ownership_nll_model

func nll_place_overlaps(int left, int right) bool {
    if left == right { return true }
    if left == 0 || right == 0 { return true }
    if left == 1 && (right == 3 || right == 4) { return true }
    if right == 1 && (left == 3 || left == 4) { return true }
    return false
}

func nll_bit_set(int bits, int bit) bool {
    value := bits / bit
    while value >= 2 {
        value = value - 2
    }
    return value == 1
}

func nll_add_point(int bits, int point) int {
    bit := 1
    i := 0
    while i < point {
        bit = bit * 2
        i = i + 1
    }
    if nll_bit_set(bits, bit) { return bits }
    return bits + bit
}

func nll_loan_covers_point(int bits, int point) bool {
    before := false
    after := false
    i := 0
    bit := 1
    while i < 8 {
        if nll_bit_set(bits, bit) {
            if i <= point { before = true }
            if i >= point { after = true }
        }
        bit = bit * 2
        i = i + 1
    }
    return before && after
}

func nll_move_conflicts(int move_place, int move_point, int loan_place, int loan_points) bool {
    return nll_loan_covers_point(loan_points, move_point) && nll_place_overlaps(move_place, loan_place)
}

func ownership_nll_model_verify() int {
    loan_points := nll_add_point(0, 0)
    loan_points = nll_add_point(loan_points, 4)
    if !nll_move_conflicts(1, 3, 1, loan_points) { return 1 }
    if nll_move_conflicts(2, 3, 1, loan_points) { return 2 }
    if nll_move_conflicts(1, 5, 1, loan_points) { return 3 }
    return 0
}
