package compile.internal
// Functional self-test for check_func (src/cmd/compile/internal/ssa/check.s).
// Builds a minimal valid ssa_func and malformed variants, asserting that
// check_func returns the expected code for each. main returns 0 when every
// case passes, or a distinct non-zero code identifying the failing case.
//
// Build & run:
//   bin/s_seed --compile-native-unit /tmp/ssa_selftest.ir \
//     src/cmd/compile/internal/ssa/value.s \
//     src/cmd/compile/internal/ssa/block.s \
//     src/cmd/compile/internal/ssa/func.s \
//     src/cmd/compile/internal/ssa/op.s \
//     src/cmd/compile/internal/ssa/check.s \
//     test/ssa-check/check_selftest.s
//   bin/s_seed --emit-standalone-amd64 /tmp/ssa_selftest.ir /tmp/ssa_selftest
//   /tmp/ssa_selftest   # exit status 0 == all checks passed

// sc_valid builds the canonical valid function: one Const value placed in the
// entry block, with the block control referencing that value.
func sc_valid() ssa_func {
    vs := ssa_value[]()
    vs = append(vs, make_value(0, "v0", op_const(), "int", int_args0(), "0"))
    b := make_block(0, "entry")
    b.values = append(b.values, 0)
    b.control = 0
    bs := ssa_bb[]()
    bs = append(bs, b)
    ssa_func { name "t", entry 0, blocks bs, values vs, next_block_id 1, next_value_id 1 }
}

func sc_int1(int x) int[] {
    xs := int[]()
    xs = append(xs, x)
    xs
}

func main() int {
    // Valid function must pass.
    if check_func(sc_valid()) != 0 { return 20 }

    // Code 1: value id does not match its slot index.
    f1 := sc_valid()
    f1.values[0].id = 5
    if check_func(f1) != 1 { return 21 }

    // Code 2: value argument references a value out of range.
    f2 := sc_valid()
    f2.values[0].op = op_copy()
    f2.values[0].args = sc_int1(99)
    if check_func(f2) != 2 { return 22 }

    // Code 3: block value id references a value out of range.
    f3 := sc_valid()
    f3.blocks[0].values = sc_int1(99)
    if check_func(f3) != 3 { return 23 }

    // Code 4: block control references a value out of range (upper bound).
    f4 := sc_valid()
    f4.blocks[0].control = 99
    if check_func(f4) != 4 { return 24 }

    // Code 4: block control is negative (lower bound).
    f4b := sc_valid()
    f4b.blocks[0].control = 0 - 1
    if check_func(f4b) != 4 { return 25 }

    // Code 5: two blocks share the same id.
    f5 := sc_valid()
    f5.blocks = append(f5.blocks, make_block(0, "dup"))
    if check_func(f5) != 5 { return 26 }

    // Code 6: a successor edge references a block that does not exist.
    f6 := sc_valid()
    f6.blocks[0].succs = sc_int1(77)
    if check_func(f6) != 6 { return 27 }

    // Code 7: a predecessor edge references a block that does not exist.
    f7 := sc_valid()
    f7.blocks[0].preds = sc_int1(77)
    if check_func(f7) != 7 { return 28 }

    // Code 8: successor and predecessor edges are not crosslinked.
    f8 := sc_valid()
    b8 := make_block(1, "b1")
    b8.control = 0
    f8.blocks = append(f8.blocks, b8)
    f8.blocks[0].succs = sc_int1(1)
    if check_func(f8) != 8 { return 29 }

    // Code 9: a value is scheduled into more than one block.
    f9 := sc_valid()
    b9 := make_block(1, "b1")
    b9.values = append(b9.values, 0)
    b9.control = 0
    f9.blocks = append(f9.blocks, b9)
    if check_func(f9) != 9 { return 30 }

    // Code 10: entry block id does not reference an existing block.
    f10 := sc_valid()
    f10.entry = 99
    if check_func(f10) != 10 { return 31 }

    // Code 11: fixed-arity op has the wrong number of arguments.
    f11 := sc_valid()
    f11.values[0].op = op_add()
    if check_func(f11) != 11 { return 32 }

    // A crosslinked two-block CFG must still pass.
    fok := sc_valid()
    bok := make_block(1, "b1")
    bok.control = 0
    fok.blocks = append(fok.blocks, bok)
    fok.blocks[0].succs = sc_int1(1)
    fok.blocks[1].preds = sc_int1(0)
    if check_func(fok) != 0 { return 33 }

    // A Phi whose argument count matches its block's predecessor count passes.
    if check_func(sc_phi(1)) != 0 { return 34 }

    // Code 12: a Phi whose argument count differs from its pred count.
    if check_func(sc_phi(2)) != 12 { return 35 }

    // Code 13: a non-Phi value that lists itself as an argument.
    f13 := sc_valid()
    f13.values[0].op = op_copy()
    f13.values[0].args = sc_int1(0)
    if check_func(f13) != 13 { return 36 }

    // A Phi that references itself (loop phi) is permitted by the self-ref rule.
    fphi := sc_phi(1)
    fphi.values[1].args = sc_int1(1)
    if check_func(fphi) != 0 { return 37 }

    0
}

// sc_phi builds a two-block CFG (entry -> b1) where b1 holds a Phi with
// phi_args arguments and exactly one predecessor. With phi_args == 1 the
// function is well formed; any other count violates the Phi invariant.
func sc_phi(int phi_args) ssa_func {
    args := int[]()
    a := 0
    for a < phi_args {
        args = append(args, 0)
        a = a + 1
    }
    vs := ssa_value[]()
    vs = append(vs, make_value(0, "v0", op_const(), "int", int_args0(), "0"))
    vs = append(vs, make_value(1, "v1", op_phi(), "int", args, ""))
    entry := make_block(0, "entry")
    entry.values = append(entry.values, 0)
    entry.control = 0
    entry.succs = append(entry.succs, 1)
    body := make_block(1, "b1")
    body.values = append(body.values, 1)
    body.control = 1
    body.preds = append(body.preds, 0)
    bs := ssa_bb[]()
    bs = append(bs, entry)
    bs = append(bs, body)
    ssa_func { name "p", entry 0, blocks bs, values vs, next_block_id 2, next_value_id 2 }
}
