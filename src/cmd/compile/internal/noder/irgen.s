package compile.internal.noder

use s.item
use s.source_file
use std.vec.vec

func lower_to_ir(source_file ast) vec[ir_node] {
    var out = vec[ir_node]()
    var i = 0
    while i < ast.items.len() {
        switch ast.items[i] {
            item.function(fn) : out.push(ir_node {
                op: "fn",
                payload: fn.sig.name,
            }),
            item.struct(st) : out.push(ir_node {
                op: "struct",
                payload: st.name,
            }),
            item.enum(en) : out.push(ir_node {
                op: "enum",
                payload: en.name,
            }),
            item.trait(tr) : out.push(ir_node {
                op: "trait",
                payload: tr.name,
            }),
            item.impl(im) : out.push(ir_node {
                op: "impl",
                payload: im.target,
            }),
            item.const(cn) : out.push(ir_node {
                op: "const",
                payload: cn.name,
            }),
        }
        i = i + 1
    }
    out
}
}
