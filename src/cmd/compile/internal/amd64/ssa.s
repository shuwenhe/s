package compile.internal.amd64

func ssa_mark_moves(ssa_block mut block) ssa_block {
    var flive = block.flags_live_at_end
    var ci = 0
    while ci < block.controls.len() {
        if block.controls[ci].flags {
            flive = true
        }
        ci = ci + 1
    }

    var i = block.values.len() - 1
    while i >= 0 {
        var v = block.values[i]
        if flive && (v.op == "OpAMD64MOVLconst" || v.op == "OpAMD64MOVQconst") {
            v.marked = true
            v.aux = "mark"
            block.values.set(i, v)
        }
        if v.flags {
            flive = false
        }
        var ai = 0
        while ai < v.args.len() {
            if v.args[ai] == "flags" {
                flive = true
            }
            ai = ai + 1
        }
        i = i - 1
    }
    block
}

func is_gp_reg(int r) bool {
    r >= 1 && r <= 16
}

func is_fp_reg(int r) bool {
    r >= 100 && r <= 131
}

func is_k_reg(int r) bool {
    r >= 200 && r <= 207
}

func is_low_fp_reg(int r) bool {
    r >= 100 && r <= 115
}

func load_by_reg_width(int reg, int width) string {
    if !is_fp_reg(reg) && !is_k_reg(reg) {
        if width == 1 {
            return "MOVBLZX"
        }
        if width == 2 {
            return "MOVWLZX"
        }
    }
    return store_by_reg_width(reg, width)
}

func store_by_reg_width(int reg, int width) string {
    if is_fp_reg(reg) {
        if width == 4 {
            return "MOVSS"
        }
        if width == 8 {
            return "MOVSD"
        }
        if width == 16 {
            if is_low_fp_reg(reg) {
                return "MOVUPS"
            }
            return "VMOVDQU"
        }
        if width == 32 {
            return "VMOVDQU"
        }
        if width == 64 {
            return "VMOVDQU64"
        }
    }
    if is_k_reg(reg) {
        return "KMOVQ"
    }
    if width == 1 {
        return "MOVB"
    }
    if width == 2 {
        return "MOVW"
    }
    if width == 4 {
        return "MOVL"
    }
    if width == 8 {
        return "MOVQ"
    }
    "MOVQ"
}

func move_by_regs_width(int dest, int src, int width) string {
    if is_fp_reg(dest) && is_fp_reg(src) {
        if is_low_fp_reg(dest) && is_low_fp_reg(src) && width <= 16 {
            return "MOVUPS"
        }
        if width <= 32 {
            return "VMOVDQU"
        }
        return "VMOVDQU64"
    }
    if is_k_reg(dest) || is_k_reg(src) {
        return "KMOVQ"
    }
    if width <= 4 {
        return "MOVL"
    }
    if width == 8 {
        return "MOVQ"
    }
    if width == 16 {
        if is_low_fp_reg(dest) && is_low_fp_reg(src) {
            return "MOVUPS"
        }
        return "VMOVDQU"
    }
    if width == 32 {
        return "VMOVDQU"
    }
    if width == 64 {
        return "VMOVDQU64"
    }
    "MOVQ"
}

func ssa_gen_value(ssa_value v) string {
    if ssa_gen_simd_value(v) {
        return "simd:" + simd_opcode_class(v.op)
    }
    if v.op == "OpAMD64ADDQ" {
        return "ADDQ"
    }
    if v.op == "OpAMD64ADDL" {
        return "ADDL"
    }
    if starts_with(v.op, "OpAMD64DIV") {
        return "DIV"
    }
    if starts_with(v.op, "OpAMD64MOV") {
        return "MOV"
    }
    "GENERIC"
}

func ssa_gen_block(string kind) string {
    if kind == "plain" {
        return "JMP"
    }
    if kind == "if" {
        return "JNE"
    }
    if kind == "ret" {
        return "RET"
    }
    "BLOCK"
}

func load_reg_result(string type_name) string {
    if type_name == "float" || type_name == "float64" || type_name == "float32" {
        return "X0"
    }
    if type_name == "ptr" {
        return "AX"
    }
    "AX"
}

func spill_arg_reg(int index) string {
    return "spill+" + to_string(index * 8)
}

func starts_with(string text, string prefix) bool {
    if text.len() < prefix.len() {
        return false
    }
    var i = 0
    while i < prefix.len() {
        if text[i] != prefix[i] {
            return false
        }
        i = i + 1
    }
    true
}
