package compile.internal.ir.types

// Compiler internal type representations (草案)

enum TypeKind {
    primitive,
    pointer,
    slice,
    named,
    generic,
}

struct Type {
    TypeKind kind,
    string name, // e.g. "int32", or base name for named/generic
    option[Type] inner, // pointer/slice inner type
    vec[Type] params, // generic params
}

func NewPrimitive(string name) Type { Type { kind: TypeKind::primitive, name: name } }
func NewPointer(Type inner) Type { Type { kind: TypeKind::pointer, inner: option[Type].some(inner) } }
func NewSlice(Type inner) Type { Type { kind: TypeKind::slice, inner: option[Type].some(inner) } }
func NewNamed(string name, vec[Type] params) Type { Type { kind: TypeKind::named, name: name, params: params } }

func TypeToString(Type t) string {
    switch t.kind {
        TypeKind::primitive : t.name,
        TypeKind::pointer : "&" + TypeToString(t.inner.unwrap()),
        TypeKind::slice : "[]" + TypeToString(t.inner.unwrap()),
        TypeKind::named : t.name,
        TypeKind::generic : t.name,
    }
}
