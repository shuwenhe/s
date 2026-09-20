package compile.internal.canonical_type

import (
    "compile.internal.semantic"
    "std"
    "std.option"
)

// M2 MINIMAL: Primitive, Declared, Pointer only
// Reference, Slice, FixedArray deferred to Phase 2

enum canonical_type_kind {
    primitive_kind,
    declared_kind,
    pointer_kind,
}

struct canonical_type {
    kind canonical_type_kind
    
    // For primitive_kind: name of primitive (int, bool, string, etc.)
    primitive_name string
    
    // For declared_kind: reference to the declaration
    declared_ref option[semantic.declaration_ref]
    
    // For pointer_kind: child type
    child option[canonical_type]
}

// Construct Primitive(kind)
func primitive(string name) canonical_type {
    canonical_type {
        kind: canonical_type_kind.primitive_kind,
        primitive_name: name,
        declared_ref: std.option.none,
        child: std.option.none,
    }
}

// Construct Declared(DeclarationRef)
func declared(semantic.declaration_ref ref) canonical_type {
    canonical_type {
        kind: canonical_type_kind.declared_kind,
        primitive_name: "",
        declared_ref: std.option.some(ref),
        child: std.option.none,
    }
}

// Construct Pointer(Type)
func pointer(canonical_type inner) canonical_type {
    canonical_type {
        kind: canonical_type_kind.pointer_kind,
        primitive_name: "",
        declared_ref: std.option.none,
        child: std.option.some(inner),
    }
}

// canonical_same_type: Semantic equality of types
// Recursively compares structure and identity
func canonical_same_type(canonical_type left, canonical_type right) bool {
    // Kind must match
    if left.kind != right.kind {
        return false
    }
    
    switch left.kind {
        canonical_type_kind.primitive_kind : {
            // Primitives equal iff names equal
            return left.primitive_name == right.primitive_name
        }
        canonical_type_kind.declared_kind : {
            // Declared types equal iff DeclarationRefs equal
            if left.declared_ref.is_none() || right.declared_ref.is_none() {
                return left.declared_ref.is_none() && right.declared_ref.is_none()
            }
            return semantic.declaration_ref_equal(
                left.declared_ref.unwrap(),
                right.declared_ref.unwrap()
            )
        }
        canonical_type_kind.pointer_kind : {
            // Pointers equal iff children equal (recursive)
            if left.child.is_none() || right.child.is_none() {
                return left.child.is_none() && right.child.is_none()
            }
            return canonical_same_type(
                left.child.unwrap(),
                right.child.unwrap()
            )
        }
    }
    
    false
}

// canonical_type_to_string: For debugging
func canonical_type_to_string(canonical_type t) string {
    switch t.kind {
        canonical_type_kind.primitive_kind : {
            return t.primitive_name
        }
        canonical_type_kind.declared_kind : {
            if t.declared_ref.is_none() {
                return "unknown"
            }
            return ir.declaration_ref_display(t.declared_ref.unwrap())
        }
        canonical_type_kind.pointer_kind : {
            if t.child.is_none() {
                return "*unknown"
            }
            return "*" + canonical_type_to_string(t.child.unwrap())
        }
    }
    "invalid"
}
