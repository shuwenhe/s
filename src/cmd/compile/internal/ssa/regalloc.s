package compile.internal.ssa
use std.slices

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
    reg_assign[] assigns
    int spills
}

func interval_less(live_interval a, live_interval b) bool {
    if a.start != b.start {
        return a.start < b.start
    }
    a.end < b.end
}

func sort_intervals(live_interval[] ivs) {
    i := 0
    for i < len(ivs) {
        j := i + 1
        for j < len(ivs) {
            if interval_less(ivs[j], ivs[i]) {
                t := ivs[i]
                ivs[i] = ivs[j]
                ivs[j] = t
            }
            j = j + 1
        }
        i = i + 1
    }
}

func build_positions(ssa_func f) int[] {
    pos := int[]()
    i := 0
    for i < len(f.values) {
        pos = append(pos, -1)
        i = i + 1
    }
    p := 0
    bi := 0
    for bi < len(f.blocks) {
        j := 0
        for j < f.blocks[bi]len(.values) {
            id := f.blocks[bi].values[j]
            if id >= 0 && id < len(pos) && pos[id] < 0 {
                pos[id] = p
                p = p + 1
            }
            j = j + 1
        }
        bi = bi + 1
    }
    i = 0
    for i < len(pos) {
        if pos[i] < 0 {
            pos[i] = p
            p = p + 1
        }
        i = i + 1
    }
    pos
}

func compute_live_intervals(ssa_func f) live_interval[] {
    pos := build_positions(f)
    ivs := live_interval[]()
    i := 0
    for i < len(f.values) {
        if !f.values[i].removed {
            need := f.values[i].uses > 0 || op_has_side_effect(f.values[i].op)
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
    for i < len(f.values) {
        if f.values[i].removed {
            i = i + 1
            continue
        }
        use_pos := pos[i]
        j := 0
        for j < f.values[i]len(.args) {
            arg := f.values[i].args[j]
            k := 0
            for k < len(ivs) {
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
    bi := 0
    for bi < len(f.blocks) {
        ctrl := f.blocks[bi].control
        if ctrl >= 0 {
            use_pos := 0
            if f.blocks[bi]len(.values) > 0 {
                tail := f.blocks[bi].values[f.blocks[bi]len(.values) - 1]
                use_pos = pos[tail]
            }
            k := 0
            for k < len(ivs) {
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

func active_expire(live_interval[] active, int point) {
    keep := live_interval[]()
    i := 0
    for i < len(active) {
        if active[i].end >= point {
            keep = append(keep, active[i])
        }
        i = i + 1
    }
    active = keep
}

func assigned_reg(reg_assign[] assigns, int value_id) string {
    i := 0
    for i < len(assigns) {
        if assigns[i].value_id == value_id {
            return assigns[i].reg
        }
        i = i + 1
    }
    ""
}

func run_regalloc(ssa_func f, int reg_count) regalloc_result {
    ivs := compute_live_intervals(f)
    assigns := reg_assign[]()
    active := live_interval[]()
    spills := 0
    i := 0
    for i < len(ivs) {
        cur := ivs[i]
        active_expire(active, cur.start)
        if reg_count <= 0 {
            assigns = append(assigns, reg_assign { value_id: cur.value_id, reg: "spill" + to_string(spills), spilled: true })
            spills = spills + 1
            i = i + 1
            continue
        }
        if len(active) < reg_count {
            used := string[]()
            ai := 0
            for ai < len(active) {
                r := assigned_reg(assigns, active[ai].value_id)
                if r != "" {
                    used = append(used, r)
                }
                ai = ai + 1
            }
            picked := ""
            rix := 0
            for rix < reg_count {
                cand := "r" + to_string(rix)
                seen := false
                ui := 0
                for ui < len(used) {
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
            assigns = append(assigns, reg_assign { value_id: cur.value_id, reg: picked, spilled: false })
            active = append(active, cur)
        } else {
            far_i := 0
            k := 1
            for k < len(active) {
                if active[k].end > active[far_i].end {
                    far_i = k
                }
                k = k + 1
            }
            if active[far_i].end > cur.end {
                stolen_reg := assigned_reg(assigns, active[far_i].value_id)
                assigns = append(assigns, reg_assign { value_id: cur.value_id, reg: stolen_reg, spilled: false })
                assigns.push(reg_assign {
                    value_id: active[far_i].value_id,
                    reg: "spill" + to_string(spills),
                    spilled: true,
                })
                spills = spills + 1
                active[far_i] = cur
            } else {
                assigns = append(assigns, reg_assign { value_id: cur.value_id, reg: "spill" + to_string(spills), spilled: true })
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
