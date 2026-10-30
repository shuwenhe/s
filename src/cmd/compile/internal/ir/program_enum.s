package compile.internal.ir.lower
import ("compile.internal.ast"; "compile.internal.mir")

struct program_enum_result {
    mir_program_enum[] enums
    string error
}

func program_collect_enums(source_file source) program_enum_result {
    output := mir_program_enum[]()
    i := 0
    for i < len(source.items) {
        switch source.items[i] {
            item.enum(declaration): {
                symbol := program_item_package(source, i) + "." + declaration.name
                if len(declaration.generics) != 0 { return program_enum_result { enums: output, error: "generic enum requires monomorphization: " + symbol } }
                payload := false
                payload_index := 0
                for payload_index < len(declaration.variants) {
                    if declaration.variants[payload_index].payload.is_some() { payload = true }
                    payload_index = payload_index + 1
                }
                if !payload {
                variants := string[]()
                tags := int[]()
                tag := 0
                v := 0
                for v < len(declaration.variants) {
                    variant := declaration.variants[v]
                    if variant.payload.is_some() { return program_enum_result { enums: output, error: "enum payload requires layout lowering: " + symbol } }
                    if variant.has_explicit_value { tag = variant.explicit_value }
                    variants = append(variants, variant.name)
                    tags = append(tags, tag)
                    if tag == 4611686018427387903 && v + 1 < len(declaration.variants) && !declaration.variants[v + 1].has_explicit_value { return program_enum_result { enums: output, error: "enum discriminant overflow: " + symbol } }
                    if tag < 4611686018427387903 { tag = tag + 1 }
                    v = v + 1
                }
                output = append(output, mir_program_enum { symbol: symbol, variants: variants, tags: tags })
                }
            }
            _ : (),
        }
        i = i + 1
    }
    return program_enum_result { enums: output, error: mir_program_enums_error(output) }
}

func program_enum_type(string type_name, string package_name, mir_program_enum[] enums) string {
    if mir_program_enum_index(enums, package_name + "." + type_name) >= 0 { return package_name + "." + type_name }
    return type_name
}

func program_enum_constant(program_lower_state initial, string package_name, string path) program_lower_state {
    state := initial
    if path == "" {
        state.error = "internal error: empty path in enum constant lookup for package " + package_name
        return state
    }
    e := 0
    for e < len(state.enums) {
        enumeration := state.enums[e]
        v := 0
        for v < len(enumeration.variants) {
            symbol := enumeration.symbol + "." + enumeration.variants[v]
            if path == symbol || package_name + "." + path == symbol {
                id := state.next_value
                state.next_value = id + 1
                enum_type := enumeration.symbol
                state.instructions = append(state.instructions, mir_program_instruction { op: "const_enum", result_ids: [id], result_types: [enum_type], operands: int[](), integer_value: enumeration.tags[v], symbol: symbol })
                state.expression_value = id
                return state
            }
            v = v + 1
        }
        e = e + 1
    }
    state.error = "unknown enum member: " + path + " in " + package_name
    return state
}
