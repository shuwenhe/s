package compile.internal.canonical_type

import (
    "compile.internal.semantic"
    "std"
    "std.option"
)

enum canonical_type_kind {
    primitive_kind,
    declared_kind,
    pointer_kind,
}

struct canonical_type {
    kind canonical_type_kind
    
    primitive_name string
    
    declared_ref option[semantic.declaration_ref]
    
    child option[canonical_type]
}

func primitive(string name) canonical_type {
    canonical_type {
        kind: canonical_type_kind.primitive_kind,
        primitive_name: name,
        declared_ref: std.option.none,
        child: std.option.none,
    }
}

func declared(semantic.declaration_ref ref) canonical_type {
    canonical_type {
        kind: canonical_type_kind.declared_kind,
        primitive_name: "",
        declared_ref: std.option.some(ref),
        child: std.option.none,
    }
}

func pointer(canonical_type inner) canonical_type {
    canonical_type {
        kind: canonical_type_kind.pointer_kind,
        primitive_name: "",
        declared_ref: std.option.none,
        child: std.option.some(inner),
    }
}

func canonical_same_type(canonical_type left, canonical_type right) bool {
    
    if left.kind != right.kind {
        return false
    }
    
    switch left.kind {
        canonical_type_kind.primitive_kind : {
            
            return left.primitive_name == right.primitive_name
        }
        canonical_type_kind.declared_kind : {
            
            if left.declared_ref.is_none() || right.declared_ref.is_none() {
                return left.declared_ref.is_none() && right.declared_ref.is_none()
            }
            return semantic.declaration_ref_equal(
                left.declared_ref.unwrap(),
                right.declared_ref.unwrap()
            )
        }
        canonical_type_kind.pointer_kind : {
            
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

func canonical_type_to_string(canonical_type t) string {
    switch t.kind {
        canonical_type_kind.primitive_kind : {
            return t.primitive_name
        }
        canonical_type_kind.declared_kind : {
            if t.declared_ref.is_none() {
                return "unknown"
            }
            return semantic.declaration_ref_display(t.declared_ref.unwrap())
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

func construct_canonical_from_string(string type_str, semantic.declaration_ref[] declarations) canonical_type {
    
    pointer_depth := 0
    i := 0
    for i < std.prelude.len(type_str) && string(type_str[i]) == "*" {
        pointer_depth = pointer_depth + 1
        i = i + 1
    }
    
    base_name := std.prelude.slice(type_str, pointer_depth, std.prelude.len(type_str))
    
    base_canonical := canonical_type {
        kind: canonical_type_kind.primitive_kind,
        primitive_name: "",
        declared_ref: std.option.none,
        child: std.option.none,
    }
    
    if base_name == "int" || base_name == "bool" || base_name == "string" {
        base_canonical = primitive(base_name)
    } else {
        
        found := semantic.find_struct_declaration(declarations, base_name)
        if found.is_some() {
            base_canonical = declared(found.unwrap())
        } else {
            
            base_canonical = primitive(base_name)
        }
    }
    
    result := base_canonical
    j := 0
    for j < pointer_depth {
        result = pointer(result)
        j = j + 1
    }
    
    result
}
