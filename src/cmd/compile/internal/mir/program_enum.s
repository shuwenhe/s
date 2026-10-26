package compile.internal

struct mir_program_enum {
    string symbol
    string[] variants
    int[] tags
}

func mir_program_enum_index(mir_program_enum[] enums, string symbol) int {
    i := 0
    for i < len(enums) { if enums[i].symbol == symbol { return i }
        i = i + 1 }
    return -1
}

func mir_program_enums_error(mir_program_enum[] enums) string {
    i := 0
    for i < len(enums) {
        enumeration := enums[i]
        if enumeration.symbol == "" || len(enumeration.variants) == 0 || len(enumeration.tags) != len(enumeration.variants) { return "invalid enum declaration" }
        j := 0
        for j < i { if enums[j].symbol == enumeration.symbol { return "duplicate enum: " + enumeration.symbol }
            j = j + 1 }
        v := 0
        for v < len(enumeration.variants) {
            if enumeration.variants[v] == "" { return "empty enum variant" }
            p := 0
            for p < v { if enumeration.variants[p] == enumeration.variants[v] { return "duplicate enum variant: " + enumeration.symbol }
                p = p + 1 }
            v = v + 1
        }
        i = i + 1
    }
    return ""
}

func mir_program_enum_instruction_error(mir_program_function function_data, mir_program_instruction instruction, int index, mir_program_enum[] enums) string {
    if instruction.op == "enum_to_int" {
        if len(instruction.operands) != 1 || instruction.result_types[0] != "int" { return "invalid enum conversion" }
        source_type := mir_program_value_type(function_data, instruction.operands[0], index)
        if mir_program_enum_index(enums, source_type) < 0 { return "enum conversion requires a declared enum" }
        return ""
    }
    if len(instruction.operands) != 0 { return "enum constant has operands" }
    owner := mir_program_enum_index(enums, instruction.result_types[0])
    if owner < 0 { return "enum constant requires a declared enum" }
    enumeration := enums[owner]
    v := 0
    for v < len(enumeration.variants) {
        if instruction.symbol == enumeration.symbol + "." + enumeration.variants[v] {
            if instruction.integer_value != enumeration.tags[v] { return "enum constant discriminant mismatch" }
            return ""
        }
        v = v + 1
    }
    return "unknown enum constant: " + instruction.symbol
}

func mir_program_physical_type(string type_name, mir_program_enum[] enums) string {
    if mir_program_enum_index(enums, type_name) >= 0 { return "int" }
    element := mir_program_array_element(type_name)
    if element != "" { return mir_program_physical_type(element, enums) + "[]" }
    return type_name
}
