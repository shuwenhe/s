package ownership_place_model

func ownership_place_local() int { return 0 }
func ownership_place_field0() int { return 1 }
func ownership_place_field1() int { return 2 }
func ownership_place_field0_0() int { return 3 }
func ownership_place_field0_1() int { return 4 }

func ownership_place_name(int place) string {
    if place == 0 { return "Local(_1)" }
    if place == 1 { return "Field(_1, 0)" }
    if place == 2 { return "Field(_1, 1)" }
    if place == 3 { return "Field(Field(_1, 0), 0)" }
    if place == 4 { return "Field(Field(_1, 0), 1)" }
    return "Unknown"
}

func ownership_place_overlaps(int left, int right) bool {
    if left == right { return true }
    if left == 0 || right == 0 { return true }
    if left == 1 && (right == 3 || right == 4) { return true }
    if right == 1 && (left == 3 || left == 4) { return true }
    return false
}

func ownership_place_model_verify() int {
    if !ownership_place_overlaps(ownership_place_local(), ownership_place_field0()) { return 1 }
    if !ownership_place_overlaps(ownership_place_field0(), ownership_place_field0_1()) { return 2 }
    if ownership_place_overlaps(ownership_place_field0(), ownership_place_field1()) { return 3 }
    if ownership_place_overlaps(ownership_place_field0_0(), ownership_place_field0_1()) { return 4 }
    if ownership_place_name(ownership_place_field1()) != "Field(_1, 1)" { return 5 }
    return 0
}
