package compile.internal.amd64

func zerorange(vec[prog] insns, int off, int cnt) vec[prog] {
    if cnt <= 0 {
        return insns
    }
    if (cnt % 8) != 0 {
        return insns
    }

    let out = insns
    let at = off
    let left = cnt
    while left >= 16 {
        out.push(prog {
            op: "MOVUPS",
            from: "X15",
            to: "SP",
            offset: at,
        })
        at = at + 16
        left = left - 16
    }
    if left != 0 {
        out.push(prog {
            op: "MOVQ",
            from: "X15",
            to: "SP",
            offset: at,
        })
    }
    out
}

func ginsnop(vec[prog] insns) vec[prog] {
    let out = insns
    out.push(prog {
        op: "XCHGL",
        from: "AX",
        to: "AX",
        offset: 0,
    })
    out
}
