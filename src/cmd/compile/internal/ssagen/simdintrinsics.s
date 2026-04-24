package compile.internal.ssagen

struct simd_intrinsic_rule {
    string name
    string op
    int lanes
    bool supported
}

func lookup_simd_intrinsic(string arch, string fn_name) simd_intrinsic_rule {
    var has_simd = arch_has_simd(arch)
    if fn_name == "runtime.addv4i32" {
        return simd_intrinsic_rule { name: fn_name, op: "AddV4I32", lanes: 4, supported: has_simd }
    }
    if fn_name == "runtime.addv2f64" {
        return simd_intrinsic_rule { name: fn_name, op: "AddV2F64", lanes: 2, supported: has_simd }
    }
    simd_intrinsic_rule { name: fn_name, op: "", lanes: 0, supported: false }
}

func has_simd_intrinsic(string arch, string fn_name) bool {
    lookup_simd_intrinsic(arch, fn_name).supported
}
