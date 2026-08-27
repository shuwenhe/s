package compile.internal.ssa

func dump_func(ssa_func f) string {
    out := "ssa-func " + f.name + "\n"
    bi := 0
    for bi < len(f.blocks) {
        b := f.blocks[bi]
        out = out + "block b" + to_string(b.id) + " kind=" + b.kind + "\n"
        i := 0
        for i < len(b.values) {
            id := b.values[i]
            v := f.values[id]
            out = out + "  v" + to_string(v.id) + " " + v.op + " " + v.ty
            if v.literal != "" {
                out = out + " lit=" + v.literal
            }
            if len(v.args) > 0 {
                out = out + " args="
                j := 0
                for j < len(v.args) {
                    if j > 0 {
                        out = out + ","
                    }
                    out = out + "v" + to_string(v.args[j])
                    j = j + 1
                }
            }
            out = out + "\n"
            i = i + 1
        }
        if b.control >= 0 {
            out = out + "  ctrl=v" + to_string(b.control) + "\n"
        }
        bi = bi + 1
    }
    out
}
