package compile.internal.noder

use s.item
use s.source_file
use std.vec.vec

func collect_exports(source_file ast) vec[export_record] {
    var out = vec[export_record]()
    var i = 0
    while i < ast.items.len() {
        switch ast.items[i] {
            item.function(fn) : {
                if fn.is_public {
                    out.push(export_record { name: fn.sig.name, kind: "func" })
                }
            }
            item.struct(st) : {
                if st.is_public {
                    out.push(export_record { name: st.name, kind: "struct" })
                }
            }
            item.enum(en) : {
                if en.is_public {
                    out.push(export_record { name: en.name, kind: "enum" })
                }
            }
            item.trait(tr) : {
                if tr.is_public {
                    out.push(export_record { name: tr.name, kind: "trait" })
                }
            }
            item.const(cn) : out.push(export_record { name: cn.name, kind: "const" }),
            _ : (),
        }
        i = i + 1
    }
    out
}

func emit_export_payload(vec[export_record] exports) string {
    var out = "export-data version=1\n"
    var i = 0
    while i < exports.len() {
        out = out + exports[i].kind + " " + exports[i].name + "\n"
        i = i + 1
    }
    out
}
