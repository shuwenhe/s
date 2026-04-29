package compile.internal.ssa

use std.vec.vec

struct reg_assign {
    int value_id
    string reg
    bool spilled
}

struct live_interval {
    int value_id
    int start
    int end
}

struct regalloc_result {
    vec[reg_assign] assigns
    int spills
}

func interval_less(live_interval a, live_interval b) bool {
    if a.start != b.start {
        return a.start < b.start
    }
    a.end < b.end
}

func sort_intervals(mut vec[live_interval] ivs) {
    let i = 0
    while i < ivs.len() {
        let j = i + 1
        while j < ivs.len() {
            if interval_less(ivs[j], ivs[i]) {
                let t = ivs[i]
                ivs[i] = ivs[j]
                ivs[j] = t
            }
            j = j + 1
        }
        i = i + 1
    }
}

func build_positions(ssa_func f) vec[int] {
    let pos = vec[int]()
    let i = 0
    while i < f.values.len() {
        pos.push(-1)
        i = i + 1
    }
    let p = 0
    let bi = 0
    while bi < f.blocks.len() {
        let j = 0
        while j < f.blocks[bi].values.len() {
            let id = f.blocks[bi].values[j]
            if id >= 0 && id < pos.len() && pos[id] < 0 {
                pos[id] = p
                p = p + 1
            }
            j = j + 1
        }
        bi = bi + 1
    }
    i = 0
    while i < pos.len() {
        if pos[i] < 0 {
            pos[i] = p
            p = p + 1
        }
        i = i + 1
    }
    pos
}

func compute_live_intervals(ssa_func f) vec[live_interval] {
    let pos = build_positions(f)
    let ivs = vec[live_interval]()
    let i = 0
    while i < f.values.len() {
        if !f.values[i].removed {
            let need = f.values[i].uses > 0 || op_has_side_effect(f.values[i].op)
            if need {
                ivs.push(live_interval {
                    value_id: i,
                    start: pos[i],
                    end: pos[i],
                })
            }
        }
        i = i + 1
    }

    i = 0
    while i < f.values.len() {
        if f.values[i].removed {
            i = i + 1
            continue
        }
        let use_pos = pos[i]
        let j = 0
        while j < f.values[i].args.len() {
            let arg = f.values[i].args[j]
            let k = 0
            while k < ivs.len() {
                if ivs[k].value_id == arg && use_pos > ivs[k].end {
                    ivs[k].end = use_pos
                    break
                }
                k = k + 1
            }
            j = j + 1
        }
        i = i + 1
    }

    let bi = 0
    while bi < f.blocks.len() {
        let ctrl = f.blocks[bi].control
        if ctrl >= 0 {
            let use_pos = 0
            if f.blocks[bi].values.len() > 0 {
                let tail = f.blocks[bi].values[f.blocks[bi].values.len() - 1]
                use_pos = pos[tail]
            }
            let k = 0
            while k < ivs.len() {
                if ivs[k].value_id == ctrl && use_pos > ivs[k].end {
                    ivs[k].end = use_pos
                    break
                }
                k = k + 1
            }
        }
        bi = bi + 1
    }

    sort_intervals(ivs)
    ivs
}

func active_expire(mut vec[live_interval] active, int point) {
    let keep = vec[live_interval]()
    let i = 0
    while i < active.len() {
        if active[i].end >= point {
            keep.push(active[i])
        }
        i = i + 1
    }
    active = keep
}

func assigned_reg(vec[reg_assign] assigns, int value_id) string {
    let i = 0
    while i < assigns.len() {
        if assigns[i].value_id == value_id {
            return assigns[i].reg
        }
        i = i + 1
    }
    ""
}

func run_regalloc(ssa_func f, int reg_count) regalloc_result {
    let ivs = compute_live_intervals(f)
    let assigns = vec[reg_assign]()
    let active = vec[live_interval]()
    let spills = 0

    let i = 0
    while i < ivs.len() {
        let cur = ivs[i]
        active_expire(active, cur.start)

        if reg_count <= 0 {
            assigns.push(reg_assign { value_id: cur.value_id, reg: "spill" + to_string(spills), spilled: true })
            spills = spills + 1
            i = i + 1
            continue
        }

        if active.len() < reg_count {
            let used = vec[string]()
            let ai = 0
            while ai < active.len() {
                let r = assigned_reg(assigns, active[ai].value_id)
                if r != "" {
                    used.push(r)
                }
                ai = ai + 1
            }
            let picked = ""
            let rix = 0
            while rix < reg_count {
                let cand = "r" + to_string(rix)
                let seen = false
                let ui = 0
                while ui < used.len() {
                    if used[ui] == cand {
                        seen = true
                        break
                    }
                    ui = ui + 1
                }
                if !seen {
                    picked = cand
                    break
                }
                rix = rix + 1
            }
            if picked == "" {
                picked = "r0"
            }
            assigns.push(reg_assign { value_id: cur.value_id, reg: picked, spilled: false })
            active.push(cur)
        } else {
            let far_i = 0
            let k = 1
            while k < active.len() {
                if active[k].end > active[far_i].end {
                    far_i = k
                }
                k = k + 1
            }
            if active[far_i].end > cur.end {
                let stolen_reg = assigned_reg(assigns, active[far_i].value_id)
                assigns.push(reg_assign { value_id: cur.value_id, reg: stolen_reg, spilled: false })
                assigns.push(reg_assign {
                    value_id: active[far_i].value_id,
                    reg: "spill" + to_string(spills),
                    spilled: true,
                })
                spills = spills + 1
                active[far_i] = cur
            } else {
                assigns.push(reg_assign { value_id: cur.value_id, reg: "spill" + to_string(spills), spilled: true })
                spills = spills + 1
            }
        }
        i = i + 1
    }

    regalloc_result {
        assigns: assigns,
        spills: spills,
    }
}
