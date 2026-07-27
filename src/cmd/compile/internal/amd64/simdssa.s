package compile.internal.amd64

func ssa_gen_simd_value(ssa_value v) bool {
    if starts_with(v.op, "simd.") {
        return true
    }
    if starts_with(v.op, "OpAMD64V") {
        return true
    }
    false
}

func simd_opcode_class(string op) string {
    if starts_with(op, "OpAMD64VAES") {
        return "aes"
    }
    if starts_with(op, "OpAMD64VPMOV") {
        return "pack"
    }
    if starts_with(op, "OpAMD64VADD") || starts_with(op, "OpAMD64VSUB") || starts_with(op, "OpAMD64VMUL") {
        return "arith"
    }
    if starts_with(op, "OpAMD64VPCM") {
        return "compare"
    }
    if starts_with(op, "OpAMD64VPSHU") {
        return "shuffle"
    }
    if starts_with(op, "OpAMD64V") {
        return "generic"
    }
    "non-simd"
}

func starts_with(string text, string prefix) bool {
    if text.len() < prefix.len() {
        return false
    }
    let i = 0
    while i < prefix.len() {
        if text[i] != prefix[i] {
            return false
        }
        i = i + 1
    }
    true
}
