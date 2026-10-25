package compile.internal

func emit_canonical_mir(string source) string {
    // Use the same typed, validated MIR producer consumed by native SSA
    // lowering. This entrypoint is a text dump, not another bootstrap format.
    lowered := canonical_source_to_mir(source)
    if lowered.error != "" {
        return "mir-error: " + lowered.error + "\n"
    }
    return dump_canonical_mir_program(lowered.program)
}

func canonical_mir_ids(int[] values) string {
    out := ""
    i := 0
    for i < len(values) {
        if i > 0 { out = out + "," }
        out = out + amd64_integer(values[i])
        i = i + 1
    }
    return out
}

func canonical_mir_types(string[] values) string {
    out := ""
    i := 0
    for i < len(values) {
        if i > 0 { out = out + "," }
        out = out + values[i]
        i = i + 1
    }
    return out
}

func dump_canonical_mir_program(mir_program program) string {
    out := "mir-program-v1 package=" + program.package_name + " entry=" + program.entry_symbol + "\n"
    e := 0
    for e < len(program.enums) {
        enumeration := program.enums[e]
        v := 0
        for v < len(enumeration.variants) {
            out = out + "enum " + enumeration.symbol + " " + enumeration.variants[v] + "=" + amd64_integer(enumeration.tags[v]) + "\n"
            v = v + 1
        }
        e = e + 1
    }
    f := 0
    for f < len(program.functions) {
        function_data := program.functions[f]
        external := "false"
        if function_data.external { external = "true" }
        out = out + "function " + function_data.symbol + " external=" + external + "\n"
        p := 0
        for p < len(function_data.params) {
            parameter := function_data.params[p]
            out = out + "parameter " + amd64_integer(parameter.value_id) + " name=" + parameter.name + " type=" + parameter.type_name + "\n"
            p = p + 1
        }
        out = out + "results " + canonical_mir_types(function_data.result_types) + "\n"
        b := 0
        for b < len(function_data.blocks) {
            block := function_data.blocks[b]
            out = out + "block " + amd64_integer(block.id) + "\n"
            i := 0
            for i < len(block.instructions) {
                instruction := block.instructions[i]
                out = out + "instruction " + instruction.op
                    + " results=" + canonical_mir_ids(instruction.result_ids)
                    + " types=" + canonical_mir_types(instruction.result_types)
                    + " operands=" + canonical_mir_ids(instruction.operands)
                    + " integer=" + amd64_integer(instruction.integer_value)
                    + " symbol=" + instruction.symbol + "\n"
                i = i + 1
            }
            out = out + "terminator " + block.terminator + " values=" + canonical_mir_ids(block.return_values) + "\n"
            b = b + 1
        }
        f = f + 1
    }
    c := 0
    for c < len(program.calls) {
        call := program.calls[c]
        out = out + "call " + call.caller + " -> " + call.callee
            + " block=" + amd64_integer(call.block_id) + " instruction=" + amd64_integer(call.instruction_index) + "\n"
        c = c + 1
    }
    return out
}
