package compile.internal.arm64
use std.slices
struct prog {
    string op
    string from
    string to
    int offset
    string cond
}

func padframe(int frame) int {
    if (frame % 16) != 0 {
        frame = frame + (16 - (frame % 16))
    }
    frame
}

func zerorange(prog[] insns, int off, int cnt, bool ignored) prog[] {
    if (cnt % 8) != 0 {
        return insns
    }
    out := insns
    at := off + 8
    left := cnt
    for left >= 16 && at < 512 {
        out.push(prog {
            op: "STP",
            from: "ZR,ZR",
            to: "[SP]",
            offset: at,
            cond: "",
        })
        at = at + 16
        left = left - 16
    }
    for left > 0 {
        out.push(prog {
            op: "MOVD",
            from: "ZR",
            to: "[SP]",
            offset: at,
            cond: "",
        })
        at = at + 8
        left = left - 8
    }
    out
}

func ginsnop(prog[] insns) prog[] {
    out := insns
    out.push(prog {
        op: "HINT",
        from: "$0",
        to: "",
        offset: 0,
        cond: "",
    })
    out
}
