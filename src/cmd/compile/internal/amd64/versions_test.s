package compile.internal.amd64
func run_versions_test_suite() int {
    info := init_arch_info()
    if info.link_arch != "amd64" {
        return 1
    }
    if info.reg_sp != 7 {
        return 1
    }
    if info.max_width <= 0 {
        return 1
    }
    v := ssa_value {
        op: "OpAMD64MOVQconst", args []string(), flags false, marked false,
        aux: "", reg 1,
    }
    b := ssa_block {
        values: ssa_value[] { v }, controls ssa_value[](), flags_live_at_end true,
    }
    marked := ssa_mark_moves(b)
    if !marked.values[0].marked {
        return 1
    }
    simd := ssa_value {
        op: "OpAMD64VADDPS128", args []string(), flags false, marked false,
        aux: "", reg 100,
    }
    if !ssa_gen_simd_value(simd) {
        return 1
    }
    0
}
