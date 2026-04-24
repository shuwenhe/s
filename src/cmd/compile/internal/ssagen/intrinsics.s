package compile.internal.ssagen

struct intrinsic_rule {
    string name
    string op
    bool side_effect
}

func lookup_intrinsic(string fn_name) intrinsic_rule {
    if fn_name == "runtime.memmove" {
        return intrinsic_rule { name: fn_name, op: "MemMove", side_effect: true }
    }
    if fn_name == "runtime.memclrNoHeapPointers" {
        return intrinsic_rule { name: fn_name, op: "MemClr", side_effect: true }
    }
    if fn_name == "math/bits.OnesCount64" {
        return intrinsic_rule { name: fn_name, op: "Popcnt64", side_effect: false }
    }
    if fn_name == "math/bits.TrailingZeros64" {
        return intrinsic_rule { name: fn_name, op: "Ctz64", side_effect: false }
    }
    intrinsic_rule { name: fn_name, op: "", side_effect: false }
}

func has_intrinsic(string fn_name) bool {
    lookup_intrinsic(fn_name).op != ""
}

func intrinsic_op(string fn_name) string {
    lookup_intrinsic(fn_name).op
}
