package compile.internal.ssa

use std.vec.vec

struct reg_assign {
    int value_id
    string reg
    bool spilled
}

struct regalloc_result {
    vec[reg_assign] assigns
    int spills
}

func run_regalloc(ssa_func f, int reg_count) regalloc_result {
    var out = vec[reg_assign]()
    var spills = 0
    var next = 0
    var i = 0
    while i < f.values.len() {
        var v = f.values[i]
        if v.removed {
            i = i + 1
            continue
        }
        var need = v.uses > 0 || op_has_side_effect(v.op)
        if !need {
            i = i + 1
            continue
        }
        if reg_count > 0 && next < reg_count {
            out.push(reg_assign {
                value_id: v.id,
                reg: "r" + to_string(next),
                spilled: false,
            })
            next = next + 1
        } else {
            out.push(reg_assign {
                value_id: v.id,
                reg: "spill" + to_string(spills),
                spilled: true,
            })
            spills = spills + 1
        }
        i = i + 1
    }
    regalloc_result {
        assigns: out,
        spills: spills,
    }
}
