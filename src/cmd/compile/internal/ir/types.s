package compile.internal.ir.types
enum type_kind {
    primitive,
    pointer,
    slice,
    named,
    generic,
}
struct type {
    type_kind kind
    string name,
    option[type] inner,
    type[] params,
}

func new_primitive(string name) type { type { kind: type_kind::primitive, name name } }

func new_pointer(type inner) type { type { kind: type_kind::pointer, inner option[type].some(inner) } }

func new_slice(type inner) type { type { kind: type_kind::slice, inner option[type].some(inner) } }

func new_named(string name, type[] params) type { type { kind: type_kind::named, name name, params params } }

func type_to_string(type t) string {
    switch t.kind {
        type_kind::primitive : t.name,
        type_kind::pointer : "&" + type_to_string(t.inner.unwrap()),
        type_kind::slice : "[]" + type_to_string(t.inner.unwrap()),
        type_kind::named : t.name,
        type_kind::generic : t.name,
    }
}
