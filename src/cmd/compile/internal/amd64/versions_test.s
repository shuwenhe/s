package compile.internal.amd64

func run_versions_test_suite() int {
    var info = init_arch_info()
    if info.link_arch != "amd64" {
        return 1
    }
    if info.reg_sp != 7 {
        return 1
    }
    if info.max_width <= 0 {
        return 1
    }

    var v = ssa_value {
        op: "OpAMD64MOVQconst",
        args: vec[string](),
        flags: false,
        marked: false,
        aux: "",
        reg: 1,
    }
    var b = ssa_block {
        values: vec[ssa_value] { v },
        controls: vec[ssa_value](),
        flags_live_at_end: true,
    }
    var marked = ssa_mark_moves(b)
    if !marked.values[0].marked {
        return 1
    }

    var simd = ssa_value {
        op: "OpAMD64VADDPS128",
        args: vec[string](),
        flags: false,
        marked: false,
        aux: "",
        reg: 100,
    }
    if !ssa_gen_simd_value(simd) {
        return 1
    }

    0
}
