package compile.internal.semantic
import ("compile.internal.ast"; "std.option")

func canonical_enum_type(string name, declaration_ref[] declarations) string {
    base := compile.internal.typesys.base_type_name(name)
    reference := compile.internal.typesys.parse_type_ref(name)
    if reference.is_ref || reference.is_slice || reference.is_array { return name }
    index := canonical_enum_index(base, declarations)
    if index < 0 { return name }
    declaration := declarations[index]
    result := declaration.package_path + "." + declaration.path
    arguments := compile.internal.typesys.extract_type_args(name)
    if len(arguments) > 0 {
        result = result + "["
        i := 0
        for i < len(arguments) {
            if i > 0 { result = result + "," }
            result = result + canonical_enum_type(arguments[i], declarations)
            i = i + 1
        }
        result = result + "]"
    }
    return result
}

func canonical_is_enum_type(string name, declaration_ref[] declarations) bool {
    i := 0
    for i < len(declarations) {
        declaration := declarations[i]
        if declaration.kind == declaration_kind.enum_kind && name == declaration.package_path + "." + declaration.path {
            if len(declaration.generics) != 0 { return false }
            v := 0
            for v < len(declaration.variants) {
                if declaration.variants[v].payload.is_some() { return false }
                v = v + 1
            }
            return true
        }
        i = i + 1
    }
    return false
}

func canonical_enum_declarations(source_file source) declaration_ref[] {
    output := declaration_ref[]()
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.enum(declaration): output.push(declaration_ref { package_path: item_package_at(source.item_packages, i, source.pkg), kind: declaration_kind.enum_kind, path: declaration.name, generics: declaration.generics, variants: declaration.variants }),
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
                            output.push(const_binding { package_path: package_name, name: package_name + "." + name, type_name: package_name + "." + declaration.name, has_int_value: true, int_value: tag })
                            if package_name == source.pkg { output.push(const_binding { package_path: package_name, name: name, type_name: package_name + "." + declaration.name, has_int_value: true, int_value: tag }) }
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
                    if names[j] == name { errors.push(canonical_semantic_error("duplicate enum declaration: " + name)) }
                    j = j + 1
                }
                names.push(name)
                if len(declaration.variants) == 0 { errors.push(canonical_semantic_error("empty enum: " + name)) }
                j = 0
                for j < len(declaration.variants) {
                    k := 0
                    for k < j {
                        if declaration.variants[k].name == declaration.variants[j].name { errors.push(canonical_semantic_error("duplicate enum variant: " + name + "." + declaration.variants[j].name)) }
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

func canonical_enum_index(string name, declaration_ref[] declarations) int {
    base := compile.internal.typesys.base_type_name(name)
    found := -1
    i := 0
    for i < len(declarations) {
        declaration := declarations[i]
        if declaration.kind == declaration_kind.enum_kind {
            if base == declaration.package_path + "." + declaration.path { return i }
            if base == declaration.path {
                if found >= 0 { return -1 }
                found = i
            }
        }
        i = i + 1
    }
    return found
}

func canonical_enum_variant_index(declaration_ref declaration, string name) int {
    i := 0
    for i < len(declaration.variants) {
        if declaration.variants[i].name == name { return i }
        i = i + 1
    }
    return -1
}

func canonical_enum_payload(string expected_type, declaration_ref declaration, int variant_index, declaration_ref[] declarations) string {
    variant := declaration.variants[variant_index]
    if variant.payload.is_none() { return "()" }
    arguments := compile.internal.typesys.extract_type_args(expected_type)
    bindings := type_binding[]()
    i := 0
    for i < len(arguments) && i < len(declaration.generics) {
        bindings.push(type_binding { name: declaration.generics[i], type_name: arguments[i] })
        i = i + 1
    }
    declared := canonical_type_in_package(variant.payload.unwrap(), declaration.package_path, declaration.generics, declarations)
    return instantiate_type(declared, declaration.generics, bindings)
}

func canonical_check_enum_pattern(pattern value, string expected_type, string source, semantic_error[] diagnostics, declaration_ref[] declarations) pattern_check_result {
    index := canonical_enum_index(expected_type, declarations)
    if index < 0 { return check_pattern(value, expected_type, source, diagnostics) }
    declaration := declarations[index]
    switch value {
        pattern.variant(variant): {
            owner := qualified_package_part(variant.path)
            owner_index := canonical_enum_index(owner, declarations)
            variant_index := canonical_enum_variant_index(declaration, last_path_segment(variant.path))
            if owner_index != index || variant_index < 0 {
                return pattern_check_result { bindings: type_binding[](), errors: add_error(source, diagnostics, "e2006", "variant does not belong to expected enum", variant.path) }
            }
            payload := declaration.variants[variant_index].payload
            arity := 0
            if payload.is_some() { arity = 1 }
            if len(variant.args) != arity {
                return pattern_check_result { bindings: type_binding[](), errors: add_error(source, diagnostics, "e2004", "enum variant payload arity mismatch", variant.path) }
            }
            if arity == 0 { return pattern_check_result { bindings: type_binding[](), errors: 0 } }
            payload_type := canonical_enum_payload(expected_type, declaration, variant_index, declarations)
            payload_type = canonical_enum_type(payload_type, declarations)
            return canonical_check_enum_pattern(variant.args[0], payload_type, source, diagnostics, declarations)
        }
        _: return check_pattern(value, expected_type, source, diagnostics),
    }
}

func canonical_enum_constructor(string path, string[] arg_types, string contextual_type, declaration_ref[] declarations, string source, semantic_error[] diagnostics) check_result {
    index := canonical_enum_index(qualified_package_part(path), declarations)
    declaration := declarations[index]
    variant_index := canonical_enum_variant_index(declaration, qualified_decl_part(path))
    if variant_index < 0 { return check_result { type_name: "unknown", errors: add_error(source, diagnostics, "e2006", "unknown enum variant", path) } }
    variant := declaration.variants[variant_index]
    arity := 0
    if variant.payload.is_some() { arity = 1 }
    if len(arg_types) != arity { return check_result { type_name: "unknown", errors: add_error(source, diagnostics, "e2004", "enum constructor payload arity mismatch", path) } }
    bindings := type_binding[]()
    if arity == 1 {
        expected := compile.internal.typesys.parse_type_ref(canonical_type_in_package(variant.payload.unwrap(), declaration.package_path, declaration.generics, declarations))
        actual := compile.internal.typesys.parse_type_ref(arg_types[0])
        bindings = collect_type_pattern_bindings(expected, actual, declaration.generics, bindings)
        if !match_type_pattern_ref(expected, actual, declaration.generics, bindings) {
            return check_result { type_name: "unknown", errors: add_error(source, diagnostics, "e2006", "enum constructor payload type mismatch", path) }
        }
    }
    contextual_arguments := string[]()
    if canonical_enum_index(contextual_type, declarations) == index { contextual_arguments = compile.internal.typesys.extract_type_args(contextual_type) }
    result_type := declaration.package_path + "." + declaration.path
    if len(declaration.generics) > 0 {
        result_type = result_type + "["
        i := 0
        for i < len(declaration.generics) {
            if i > 0 { result_type = result_type + "," }
            argument := lookup_name_type(bindings, declaration.generics[i])
            if is_unknown(argument) && i < len(contextual_arguments) { argument = contextual_arguments[i] }
            if is_unknown(argument) { return check_result { type_name: "unknown", errors: add_error(source, diagnostics, "e2006", "cannot infer enum type argument", path) } }
            result_type = result_type + argument
            i = i + 1
        }
        result_type = result_type + "]"
    }
    return check_result { type_name: result_type, errors: 0 }
}

func canonical_enum_patterns_cover(pattern[] patterns, string expected_type, declaration_ref[] declarations) bool {
    if len(patterns) == 0 { return false }
    p := 0
    for p < len(patterns) {
        if pattern_is_wild(patterns[p]) { return true }
        p = p + 1
    }
    index := canonical_enum_index(expected_type, declarations)
    if index < 0 { return patterns_cover_type(patterns, expected_type) }
    declaration := declarations[index]
    v := 0
    for v < len(declaration.variants) {
        covered := false
        payload_patterns := pattern[]()
        p = 0
        for p < len(patterns) {
            switch patterns[p] {
                pattern.variant(variant): {
                    if last_path_segment(variant.path) == declaration.variants[v].name {
                        if len(variant.args) == 0 && declaration.variants[v].payload.is_none() { covered = true }
                        else if len(variant.args) == 1 { payload_patterns.push(variant.args[0]) }
                    }
                }
                _: (),
            }
            p = p + 1
        }
        if declaration.variants[v].payload.is_some() {
            covered = canonical_enum_patterns_cover(payload_patterns, canonical_enum_payload(expected_type, declaration, v, declarations), declarations)
        }
        if !covered { return false }
        v = v + 1
    }
    return true
}

// Effectful initializer checking needs only initializer declarations. Do not
// carry copies of every function body into those long-lived checking calls.
// Other declarations are checked by the ordinary full-file item pass.
func canonical_initializer_source(source_file file, bool globals) source_file {
    selected := source_file { pkg: file.pkg, uses: file.uses, items: item[](), item_packages: string[]() }
    i := 0
    for i < len(file.items) {
        keep := false
        switch file.items[i] {
            item.const(_): keep = !globals,
            item.var(_): keep = globals,
            _: (),
        }
        if keep {
            selected.items.push(file.items[i])
            selected.item_packages.push(item_package_at(file.item_packages, i, file.pkg))
        }
        i = i + 1
    }
    return selected
}

// Literal constant expressions need no copy of the complete function table.
// Calls/constructors retain the ordinary inference path, including diagnostics.
func canonical_const_name_type(context* canonical_const_context, string name) string {
    i := len(context.types)
    for i > 0 {
        i = i - 1
        if context.types[i].name == name {
            if context.types[i].type_name == "int" { return "int" }
            if context.types[i].type_name == "bool" { return "bool" }
            if context.types[i].type_name == "string" { return "string" }
            return "declared"
        }
    }
    return "unknown"
}

func canonical_const_type(expr value, context* canonical_const_context) canonical_inference {
    diagnostics := semantic_error[]()
    switch value {
        expr.int(_): { return canonical_inference { type_name: "int", diagnostics: diagnostics } }
        expr.string(_): { return canonical_inference { type_name: "string", diagnostics: diagnostics } }
        expr.bool(_): { return canonical_inference { type_name: "bool", diagnostics: diagnostics } }
        expr.name(name): {
            type_name := canonical_const_name_type(context, name.name)
            if type_name != "unknown" && type_name != "declared" { return canonical_inference { type_name: type_name, diagnostics: diagnostics } }
        }
        expr.binary(binary): {
            left := canonical_const_type(binary.left.value, context)
            right := canonical_const_type(binary.right.value, context)
            if left.type_name != "" && right.type_name != "" {
                inferred := canonical_binary_inference(binary.op, left.type_name, right.type_name)
                zero_division := (binary.op == "/" || binary.op == "%") && is_zero_int_expr(binary.right.value)
                return canonical_merge_const_inference(left, right, inferred, zero_division, binary.op)
            }
        }
        _: (),
    }
    return canonical_inference { type_name: "", diagnostics: diagnostics }
}

func canonical_merge_const_inference(canonical_inference left, canonical_inference right, canonical_inference inferred, bool zero_division, string op) canonical_inference {
    diagnostics := semantic_error[]()
    i := 0
    for i < len(left.diagnostics) { diagnostics.push(left.diagnostics[i]); i = i + 1 }
    i = 0
    for i < len(right.diagnostics) { diagnostics.push(right.diagnostics[i]); i = i + 1 }
    i = 0
    for i < len(inferred.diagnostics) { diagnostics.push(inferred.diagnostics[i]); i = i + 1 }
    if zero_division { diagnostics.push(semantic_error { code: "e3065", message: "division or modulo by zero is known at compile time", anchor: op }) }
    return canonical_inference { type_name: inferred.type_name, diagnostics: diagnostics }
}

// Implicit printing functions have the same exact signatures and reserved
// identities as their native MIR wrappers. Source declarations take precedence.
func canonical_native_builtin_functions(function_binding[] initial) function_binding[] {
    functions := initial
    names := ["println", "eprintln", "panic"];
    i := 0
    for i < len(names) {
        declared := false
        f := 0
        for f < len(initial) {
            if !initial[f].has_receiver && initial[f].name == names[i] { declared = true }
            f = f + 1
        }
        if !declared {
            functions = append(functions, function_binding { package_path: "__native_builtin", name: names[i], owner_type: "", has_receiver: false, receiver_mode: "value", generic_names: string[](), param_types: ["string"], return_type: "()" })
        }
        i = i + 1
    }
    return functions
}
