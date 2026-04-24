package compile.internal.arm

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

struct ssa_block {
    string kind
    vec[int] succs
    int likely
}

struct bfc_result {
    bool ok
    int lsb
    int width
}

func ssa_mark_moves() () {
}

func load_by_type(string type_name, bool signed) string {
    if type_name == "float32" {
        return "MOVF"
    }
    if type_name == "float64" {
        return "MOVD"
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
    "MOVW"
}

func store_by_type(string type_name) string {
    if type_name == "float32" {
        return "MOVF"
    }
    if type_name == "float64" {
        return "MOVD"
    }
    if type_name == "int8" || type_name == "u8" {
        return "MOVB"
    }
    if type_name == "int16" || type_name == "u16" {
        return "MOVH"
    }
    "MOVW"
}

func makeshift(int reg, int typ, int amount) int {
    if amount < 0 {
        return 0
    }
    if amount >= 32 {
        return 0
    }
    return (reg & 0xf) + typ + ((amount & 31) << 7)
}

func makeregshift(int r1, int typ, int r2) int {
    return (r1 & 0xf) + typ + ((r2 & 0xf) << 8) + (1 << 4)
}

func get_bfc(int v) bfc_result {
    if v == 0 {
        return bfc_result { ok: false, lsb: -1, width: 0 }
    }

    var lsb = 0
    var t = v
    while lsb < 32 {
        if (t % 2) == 1 {
            break
        }
        t = t / 2
        lsb = lsb + 1
    }

    var width = 0
    var u = t
    while width < 32 && (u % 2) == 1 {
        u = u / 2
        width = width + 1
    }

    if u != 0 {
        return bfc_result { ok: false, lsb: -1, width: 0 }
    }

    if lsb < 0 || lsb > 31 {
        return bfc_result { ok: false, lsb: -1, width: 0 }
    }
    if width <= 0 || width > (32 - lsb) {
        return bfc_result { ok: false, lsb: -1, width: 0 }
    }

    bfc_result { ok: true, lsb: lsb, width: width }
}

func ssa_gen_value(ssa_value value) string {
    if value.op == "OpCopy" || value.op == "OpARMMOVWreg" {
        return "MOVW"
    }
    if value.op == "OpLoadReg" {
        return load_by_type(value.type_name, value.signed)
    }
    if value.op == "OpStoreReg" {
        return store_by_type(value.type_name)
    }
    if value.op == "OpARMADD" || value.op == "OpARMADDconst" {
        return "ADD"
    }
    if value.op == "OpARMSUB" || value.op == "OpARMSUBconst" {
        return "SUB"
    }
    if value.op == "OpARMAND" || value.op == "OpARMANDconst" {
        return "AND"
    }
    if value.op == "OpARMOR" || value.op == "OpARMORconst" {
        return "ORR"
    }
    if value.op == "OpARMXOR" || value.op == "OpARMXORconst" {
        return "EOR"
    }
    if value.op == "OpARMMUL" {
        return "MUL"
    }
    if starts_with(value.op, "OpARM") {
        return "ARM_OP"
    }
    "GENERIC"
}

func ssa_gen_block(string kind, int next_succ, int likely) vec[string] {
    var out = vec[string]()

    if kind == "BlockPlain" || kind == "BlockDefer" {
        if next_succ != 0 {
            out.push("JMP")
        }
        return out
    }

    if kind == "BlockRet" {
        out.push("RET")
        return out
    }

    if kind == "BlockARMEQ" {
        if next_succ == 0 {
            out.push("BNE")
        } else {
            out.push("BEQ")
        }
        return out
    }

    if kind == "BlockARMNE" {
        if next_succ == 0 {
            out.push("BEQ")
        } else {
            out.push("BNE")
        }
        return out
    }

    if starts_with(kind, "BlockARM") {
        if likely >= 0 {
            out.push("B.cond")
            out.push("JMP")
        } else {
            out.push("B.inv")
            out.push("JMP")
        }
        return out
    }

    out.push("UNIMPL")
    out
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
