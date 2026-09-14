package ownership_drop_model

func drop_parent_state(int left, int right) int {
    if left == 0 && right == 0 { return 0 }
    if left == 1 && right == 1 { return 1 }
    return 2
}

func drop_decision(int local_state, int field0_state, int field1_state) string {
    if local_state == 0 { return "Drop(Local(_1))" }
    if local_state == 1 { return "" }
    if field1_state == 0 { return "Drop(Field(_1, 1))" }
    if field0_state == 0 { return "Drop(Field(_1, 0))" }
    return ""
}

func ownership_drop_model_verify() int {
    f0 := 1
    f1 := 0
    local := drop_parent_state(f0, f1)
    if local != 2 { return 1 }
    if drop_decision(local, f0, f1) != "Drop(Field(_1, 1))" { return 2 }
    f0 = 0
    local = drop_parent_state(f0, f1)
    if local != 0 { return 3 }
    if drop_decision(local, f0, f1) != "Drop(Local(_1))" { return 4 }
    return 0
}
