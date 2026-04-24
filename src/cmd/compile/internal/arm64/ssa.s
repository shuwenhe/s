package compile.internal.arm64

use std.vec.vec

struct ssa_value {
    string op
    vec[string] args
    int reg
    int reg0
    int aux_int
    string type_name
    bool signed
}

func ssa_mark_moves() () {
}

func load_by_type(string type_name, bool signed) string {
    if type_name == "float32" {
        return "FMOVS"
    }
    if type_name == "float64" {
        return "FMOVD"
    }
    if type_name == "int8" || type_name == "u8" {
        if signed {
            return "MOVB"
        }
        return "MOVBU"
    }
    if type_name == "int16" || type_name == "u16" {
        if signed {
            return "MOVH"
        }
        return "MOVHU"
    }
    if type_name == "int32" || type_name == "u32" {
        if signed {
            return "MOVW"
        }
        return "MOVWU"
    }
    "MOVD"
}

func store_by_type(string type_name) string {
    if type_name == "float32" {
        return "FMOVS"
    }
    if type_name == "float64" {
        return "FMOVD"
    }
    if type_name == "int8" || type_name == "u8" {
        return "MOVB"
    }
    if type_name == "int16" || type_name == "u16" {
        return "MOVH"
    }
    if type_name == "int32" || type_name == "u32" {
        return "MOVW"
    }
    "MOVD"
}

func load_by_type2(string type_name) string {
    if type_name == "float32" {
        return "FLDPS"
    }
    if type_name == "float64" {
        return "FLDPD"
    }
    if type_name == "int32" || type_name == "u32" {
        return "LDPW"
    }
    if type_name == "int" || type_name == "int64" || type_name == "u64" || type_name == "ptr" {
        return "LDP"
    }
    ""
}

func store_by_type2(string type_name) string {
    if type_name == "float32" {
        return "FSTPS"
    }
    if type_name == "float64" {
        return "FSTPD"
    }
    if type_name == "int32" || type_name == "u32" {
        return "STPW"
    }
    if type_name == "int" || type_name == "int64" || type_name == "u64" || type_name == "ptr" {
        return "STP"
    }
    ""
}

func makeshift(int reg, int typ, int amount) int {
    if amount < 0 || amount >= 64 {
        return 0
    }
    ((reg & 31) << 16) + typ + ((amount & 63) << 10)
}

func gen_indexed_operand(string op, int base, int idx) string {
    if op == "MOVDloadidx8" || op == "MOVDstoreidx8" || op == "FMOVDloadidx8" || op == "FMOVDstoreidx8" {
        return "[R" + to_string(base) + "+(R" + to_string(idx) + "<<3)]"
    }
    if op == "MOVWloadidx4" || op == "MOVWUloadidx4" || op == "MOVWstoreidx4" || op == "FMOVSloadidx4" || op == "FMOVSstoreidx4" {
        return "[R" + to_string(base) + "+(R" + to_string(idx) + "<<2)]"
    }
    if op == "MOVHloadidx2" || op == "MOVHUloadidx2" || op == "MOVHstoreidx2" {
        return "[R" + to_string(base) + "+(R" + to_string(idx) + "<<1)]"
    }
    return "[R" + to_string(base) + "+R" + to_string(idx) + "]"
}

func ssa_gen_value(ssa_value value) string {
    if value.op == "OpCopy" || value.op == "OpARM64MOVDreg" {
        return "MOVD"
    }
    if value.op == "OpARM64MOVDnop" || value.op == "OpARM64ZERO" {
        return "NOP"
    }
    if value.op == "OpLoadReg" {
        return load_by_type(value.type_name, value.signed)
    }
    if value.op == "OpStoreReg" {
        return store_by_type(value.type_name)
    }
    if value.op == "OpArgIntReg" || value.op == "OpArgFloatReg" {
        return "SPILLPLAN"
    }
    if value.op == "OpARM64ADD" || value.op == "OpARM64ADDconst" {
        return "ADD"
    }
    if value.op == "OpARM64SUB" || value.op == "OpARM64SUBconst" {
        return "SUB"
    }
    if value.op == "OpARM64AND" {
        return "AND"
    }
    if value.op == "OpARM64OR" {
        return "ORR"
    }
    if value.op == "OpARM64XOR" {
        return "EOR"
    }
    if value.op == "OpARM64MUL" || value.op == "OpARM64MULW" {
        return "MUL"
    }
    if value.op == "OpARM64DIV" || value.op == "OpARM64UDIV" || value.op == "OpARM64DIVW" || value.op == "OpARM64UDIVW" {
        return "DIV"
    }
    if value.op == "OpARM64FADDS" || value.op == "OpARM64FADDD" {
        return "FADD"
    }
    if value.op == "OpARM64FSUBS" || value.op == "OpARM64FSUBD" {
        return "FSUB"
    }
    if value.op == "OpARM64FMULS" || value.op == "OpARM64FMULD" {
        return "FMUL"
    }
    if value.op == "OpARM64FDIVS" || value.op == "OpARM64FDIVD" {
        return "FDIV"
    }
    if starts_with(value.op, "OpARM64") {
        return "ARM64_OP"
    }
    "GENERIC"
}

func ssa_gen_block(string kind, int next_succ, int likely) vec[string] {
    var out = vec[string]()
    if kind == "BlockPlain" || kind == "BlockDefer" {
        if next_succ != 0 {
            out.push("B")
        }
        return out
    }
    if kind == "BlockRet" {
        out.push("RET")
        return out
    }
    if starts_with(kind, "BlockARM64") {
        if likely >= 0 {
            out.push("B.cond")
            out.push("B")
        } else {
            out.push("B.inv")
            out.push("B")
        }
        return out
    }
    out.push("UNIMPL")
    out
}

func load_reg_result(string type_name) string {
    if type_name == "float32" || type_name == "float64" || type_name == "float" {
        return "F0"
    }
    if type_name == "ptr" {
        return "R0"
    }
    "R0"
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
