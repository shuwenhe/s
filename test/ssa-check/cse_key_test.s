package compile.internal
// Functional test for commutative operand canonicalization in value_key and
// its effect on CSE (run_cse). Commutative ops (Add, Mul) must hash a+b and
// b+a to the same key so CSE can merge them; non-commutative ops (Sub, Div)
// must keep operand order significant. main returns 0 when all cases pass.

func ck_val(int id, string op, int a, int b) ssa_value {
    args := int[]()
    args = append(args, a)
    args = append(args, b)
    make_value(id, "v", op, "int", args, "")
}

func main() int {
    // Add is commutative: a+b and b+a share a key.
    if value_key(ck_val(2, op_add(), 0, 1)) != value_key(ck_val(3, op_add(), 1, 0)) { return 1 }
    // Mul is commutative.
    if value_key(ck_val(2, op_mul(), 0, 1)) != value_key(ck_val(3, op_mul(), 1, 0)) { return 2 }
    // Sub is NOT commutative: operand order stays significant.
    if value_key(ck_val(2, op_sub(), 0, 1)) == value_key(ck_val(3, op_sub(), 1, 0)) { return 3 }
    // Div is NOT commutative.
    if value_key(ck_val(2, op_div(), 0, 1)) == value_key(ck_val(3, op_div(), 1, 0)) { return 4 }
    // Distinct Add operands still differ from an unrelated pair.
    if value_key(ck_val(2, op_add(), 0, 1)) == value_key(ck_val(3, op_add(), 0, 2)) { return 5 }

    // End-to-end: CSE merges c = a+b and d = b+a.
    vs := ssa_value[]()
    vs = append(vs, make_value(0, "a", op_const(), "int", int_args0(), "1"))
    vs = append(vs, make_value(1, "b", op_const(), "int", int_args0(), "2"))
    ab := int[]()
    ab = append(ab, 0)
    ab = append(ab, 1)
    vs = append(vs, make_value(2, "c", op_add(), "int", ab, ""))
    ba := int[]()
    ba = append(ba, 1)
    ba = append(ba, 0)
    vs = append(vs, make_value(3, "d", op_add(), "int", ba, ""))
    b := make_block(0, "entry")
    b.values = append(b.values, 0)
    b.values = append(b.values, 1)
    b.values = append(b.values, 2)
    b.values = append(b.values, 3)
    b.control = 2
    bs := ssa_bb[]()
    bs = append(bs, b)
    f := ssa_func { name "t", entry 0, blocks bs, values vs, next_block_id 1, next_value_id 4 }
    if run_cse(f) < 1 { return 6 }

    // Sanity: without canonicalization two distinct subexpressions do not merge.
    vs2 := ssa_value[]()
    vs2 = append(vs2, make_value(0, "a", op_const(), "int", int_args0(), "1"))
    vs2 = append(vs2, make_value(1, "b", op_const(), "int", int_args0(), "2"))
    s01 := int[]()
    s01 = append(s01, 0)
    s01 = append(s01, 1)
    vs2 = append(vs2, make_value(2, "c", op_sub(), "int", s01, ""))
    s10 := int[]()
    s10 = append(s10, 1)
    s10 = append(s10, 0)
    vs2 = append(vs2, make_value(3, "d", op_sub(), "int", s10, ""))
    b2 := make_block(0, "entry")
    b2.values = append(b2.values, 0)
    b2.values = append(b2.values, 1)
    b2.values = append(b2.values, 2)
    b2.values = append(b2.values, 3)
    b2.control = 2
    bs2 := ssa_bb[]()
    bs2 = append(bs2, b2)
    f2 := ssa_func { name "t2", entry 0, blocks bs2, values vs2, next_block_id 1, next_value_id 4 }
    if run_cse(f2) != 0 { return 7 }

    0
}
