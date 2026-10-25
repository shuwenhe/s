package compile.internal.semantic
import ("compile.internal.ast"; "std.option")

func canonical_enum_type(string name, declaration_ref[] declarations) string {
    found := ""
    i := 0
    for i < len(declarations) {
        declaration := declarations[i]
        if declaration.kind == declaration_kind.enum_kind {
            full := declaration.package_path + "." + declaration.path
            if name == full { return full }
            if name == declaration.path {
                if found != "" && found != full { return name }
                found = full
            }
        }
        i = i + 1
    }
    if found != "" { return found }
    return name
}

func canonical_is_enum_type(string name, declaration_ref[] declarations) bool {
    i := 0
    for i < len(declarations) {
        declaration := declarations[i]
        if declaration.kind == declaration_kind.enum_kind && name == declaration.package_path + "." + declaration.path { return true }
        i = i + 1
    }
    return false
}

func canonical_enum_declarations(source_file source) declaration_ref[] {
    output := declaration_ref[]()
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.enum(declaration): output = append(output, declaration_ref { package_path: item_package_at(source.item_packages, i, source.pkg), kind: declaration_kind.enum_kind, path: declaration.name }),
            _ : (),
        }
        i = i + 1
    }
    return output
}

func canonical_enum_constants(source_file source) const_binding[] {
    output := const_binding[]()
    i := 0
    for i < len(source.items) {
        package_name := item_package_at(source.item_packages, i, source.pkg)
        switch source.items[i] {
            item.enum(declaration): {
                if len(declaration.generics) == 0 {
                    tag := 0
                    v := 0
                    for v < len(declaration.variants) {
                        variant := declaration.variants[v]
                        if variant.has_explicit_value { tag = variant.explicit_value }
                        if variant.payload.is_none() {
                            name := declaration.name + "." + variant.name
                            output = append(output, const_binding { package_path: package_name, name: package_name + "." + name, type_name: package_name + "." + declaration.name, has_int_value: true, int_value: tag })
                            if package_name == source.pkg { output = append(output, const_binding { package_path: package_name, name: name, type_name: package_name + "." + declaration.name, has_int_value: true, int_value: tag }) }
                        }
                        // Overflow is rejected by the declaration validator.
                        if tag < 4611686018427387903 { tag = tag + 1 }
                        v = v + 1
                    }
                }
            }
            _ : (),
        }
        i = i + 1
    }
    return output
}

func canonical_semantic_error(string message) semantic_error {
    return semantic_error { code: "e3100", message: message, stage: "semantic", severity: "error", line: 1, column: 1 }
}

func canonical_enum_errors(source_file source) semantic_error[] {
    errors := semantic_error[]()
    names := string[]()
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.enum(declaration): {
                name := item_package_at(source.item_packages, i, source.pkg) + "." + declaration.name
                j := 0
                for j < len(names) {
                    if names[j] == name { errors = append(errors, canonical_semantic_error("duplicate enum declaration: " + name)) }
                    j = j + 1
                }
                names = append(names, name)
                if len(declaration.variants) == 0 { errors = append(errors, canonical_semantic_error("empty enum: " + name)) }
                j = 0
                for j < len(declaration.variants) {
                    k := 0
                    for k < j {
                        if declaration.variants[k].name == declaration.variants[j].name { errors = append(errors, canonical_semantic_error("duplicate enum variant: " + name + "." + declaration.variants[j].name)) }
                        k = k + 1
                    }
                    j = j + 1
                }
            }
            _ : (),
        }
        i = i + 1
    }
    return errors
}
