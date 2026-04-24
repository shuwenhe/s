package compile.internal.ssa

func dump_func(ssa_func f) string {
    var out = "ssa-func " + f.name + "\n"
    var bi = 0
    while bi < f.blocks.len() {
        var b = f.blocks[bi]
        out = out + "block b" + to_string(b.id) + " kind=" + b.kind + "\n"
        var i = 0
        while i < b.values.len() {
            var id = b.values[i]
            var v = f.values[id]
            out = out + "  v" + to_string(v.id) + " " + v.op + " " + v.ty
            if v.literal != "" {
                out = out + " lit=" + v.literal
            }
            if v.args.len() > 0 {
                out = out + " args="
                var j = 0
                while j < v.args.len() {
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
