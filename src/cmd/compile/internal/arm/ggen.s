package compile.internal.arm

use std.vec.vec

struct prog {
    string op
    string from
    string to
    int offset
    string cond
}

func zerorange(vec[prog] insns, int off, int cnt, bool r0_ready) vec[prog] {
    if cnt <= 0 {
        return insns
    }

    let out = insns
    let has_r0 = r0_ready
    if !has_r0 {
        out.push(prog {
            op: "MOVW",
            from: "$0",
            to: "R0",
            offset: 0,
            cond: "",
        })
        has_r0 = true
    }

    let ptr_size = 4
    if cnt < (4 * ptr_size) {
        let i = 0
        while i < cnt {
            out.push(prog {
                op: "MOVW",
                from: "R0",
                to: "[SP]",
                offset: 4 + off + i,
                cond: "",
            })
            i = i + ptr_size
        }
        return out
    }

    if cnt <= (128 * ptr_size) {
        out.push(prog {
            op: "DUFFZERO",
            from: "SP",
            to: "R1",
            offset: 4 + off,
            cond: "",
        })
        return out
    }

    let at = 0
    while at < cnt {
        out.push(prog {
            op: "MOVW",
            from: "R0",
            to: "[R1]",
            offset: 4 + off + at,
            cond: "postinc",
        })
        at = at + ptr_size
    }
    out
}

func ginsnop(vec[prog] insns) vec[prog] {
    let out = insns
    out.push(prog {
        op: "AND",
        from: "R0",
        to: "R0",
        offset: 0,
        cond: "EQ",
    })
    out
}
