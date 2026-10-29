package compile.internal.canonical_type

import (
    "compile.internal.semantic"
    "std"
    "std.option"
)

struct canonical_type {
    string kind
    
    string primitive_name
    
    std.option.option[compile.internal.semantic.declaration_ref] declared_ref
    
    canonical_type[] child
}

func primitive(string name) canonical_type {
    canonical_type {
        kind: "primitive",
        primitive_name: name,
        declared_ref: std.option.option.none,
        child: canonical_type[](),
    }
}

func declared(compile.internal.semantic.declaration_ref ref) canonical_type {
    canonical_type {
        kind: "declared",
        primitive_name: "",
        declared_ref: std.option.option.some(ref),
        child: canonical_type[](),
    }
}

func pointer(canonical_type inner) canonical_type {
    canonical_type {
        kind: "pointer",
        primitive_name: "",
        declared_ref: std.option.option.none,
        child: [inner],
    }
}

func canonical_same_type(canonical_type left, canonical_type right) bool {
    
    if left.kind != right.kind {
        return false
    }
    
    switch left.kind {
        "primitive" : {
            
            return left.primitive_name == right.primitive_name
        }
        "declared" : {
            
            if left.declared_ref.is_none() || right.declared_ref.is_none() {
                return left.declared_ref.is_none() && right.declared_ref.is_none()
            }
            return compile.internal.semantic.declaration_ref_equal(
                left.declared_ref.unwrap(),
                right.declared_ref.unwrap()
            )
        }
        "pointer" : {
            
            if len(left.child) == 0 || len(right.child) == 0 {
                return len(left.child) == 0 && len(right.child) == 0
            }
            return canonical_same_type(
                left.child[0],
                right.child[0]
            )
        }
    }
    
    false
}

func canonical_type_to_string(canonical_type t) string {
    switch t.kind {
        "primitive" : {
            return t.primitive_name
        }
        "declared" : {
            if t.declared_ref.is_none() {
                return "unknown"
            }
            return compile.internal.semantic.declaration_ref_display(t.declared_ref.unwrap())
        }
        "pointer" : {
            if len(t.child) == 0 {
                return "*unknown"
            }
            return "*" + canonical_type_to_string(t.child[0])
        }
    }
    "invalid"
}

func construct_canonical_from_string(string type_str, compile.internal.semantic.declaration_ref[] declarations) canonical_type {
    
    pointer_depth := 0
    i := 0
    for i < std.prelude.len(type_str) && std.prelude.char_at(type_str, i) == "*" {
        pointer_depth = pointer_depth + 1
        i = i + 1
    }
    
    base_name := std.prelude.prelude_slice(type_str, pointer_depth, std.prelude.len(type_str))
    
    base_canonical := canonical_type {
        kind: "primitive",
        primitive_name: "",
        declared_ref: std.option.option.none,
        child: canonical_type[](),
    }
    
    if base_name == "int" || base_name == "bool" || base_name == "string" {
        base_canonical = primitive(base_name)
    } else {
        
        found := compile.internal.semantic.find_struct_declaration(declarations, base_name)
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
    
    return result
}
