package compile.internal.noder
use s.item
use s.source_file
use std.slices

func collect_exports(source_file ast) export_record[] {
    out := export_record[]()
    i := 0
    for i < len(ast.items) {
        switch ast.items[i] {
            item.function(fn) : {
                if fn.is_public {
                    out = append(out, export_record { name: fn.sig.name, kind: "func" })
                }
            }
            item.struct(st) : {
                if st.is_public {
                    out = append(out, export_record { name: st.name, kind: "struct" })
                }
            }
            item.enum(en) : {
                if en.is_public {
                    out = append(out, export_record { name: en.name, kind: "enum" })
                }
            }
            item.trait(tr) : {
                if tr.is_public {
                    out = append(out, export_record { name: tr.name, kind: "trait" })
                }
            }
            item.method(method) : {
                if method.method.is_public {
                    out.push(export_record {
                        name: method.receiver_type + "." + method.method.sig.name,
                        kind: "method",
                    })
                }
            }
            item.const(cn) : out = append(out, export_record { name: cn.name, kind: "const" }),
            _ : (),
        }
        i = i + 1
    }
    out
}

func emit_export_payload(export_record[] exports) string {
    out := "export-data version=1\n"
    i := 0
    for i < len(exports) {
        out = out + exports[i].kind + " " + exports[i].name + "\n"
        i = i + 1
    }
    out
}
