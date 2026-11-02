func acceptance_expect(string name, string actual, string expected) int {
    if actual != expected { eprintln(name + ": expected " + expected + ", got " + actual); return 1 }
    eprintln(name + ": " + actual)
    return 0
}
func acceptance_main() int {
    mi := mir_program_instruction { op: "const_int", result_ids: [0], result_types: ["int"] }
    mb := mir_program_block { id: 0, instructions: [mi], terminator: "return", return_values: [0] }
    mf := mir_program_function { symbol: "sample.main", result_types: ["int"], blocks: [mb] }
    if acceptance_expect("PositiveMIR", mir_program_function_error(mf, [mf]), "") != 0 { return 13 }
    mf.params.push(mir_program_parameter { value_id: 1, name: "x", type_name: "&missing" })
    if acceptance_expect("StrictMIRUnknownReference", mir_program_function_error(mf, [mf]), "unproven reference parameter: sample.main.x (&missing)") != 0 { return 14 }
    if acceptance_expect("PositiveSSA", verify_ssa_program(valid_program()), "") != 0 { return 1 }
    if acceptance_expect("PositiveCFG", verify_ssa_program(branch_program()), "") != 0 { return 2 }
    if acceptance_expect("PositiveAMD64", amd64_validate_program(valid_program()), "") != 0 { return 3 }
    emitted := emit_function_ssa_amd64(valid_program())
    if emitted.error != "" { eprintln(emitted.error); return 12 }
    eprintln("ASSEMBLY-BEGIN\n" + emitted.assembly + "ASSEMBLY-END")
    p := valid_program(); f := p.functions[0]; b := f.blocks[0]
    b.values.push(function_ssa_value { id: 1, op: "opaque", operands: [99], block_id: 0, type_name: "int" }); f.blocks[0] = b; p.functions[0] = f
    if acceptance_expect("UndefinedSSAvalue", verify_ssa_program(p), "unknown operand: sample.main") != 0 { return 4 }
    p = branch_program(); f = p.functions[0]; b = f.blocks[3]
    b.values.push(function_ssa_value { id: 2, op: "copy", operands: [1], block_id: 3, type_name: "int" }); f.blocks[3] = b; p.functions[0] = f
    if acceptance_expect("InvalidDominance", verify_ssa_program(p), "nondominating operand: sample.main") != 0 { return 5 }
    p = branch_program(); f = p.functions[0]; b = f.blocks[3]
    b.values.push(function_ssa_value { id: 2, op: "phi", operands: [1], block_id: 3, type_name: "int" }); f.blocks[3] = b; p.functions[0] = f
    if acceptance_expect("PhiInputs", verify_ssa_program(p), "phi operand count: sample.main") != 0 { return 6 }
    p = valid_program(); f = p.functions[0]; b = f.blocks[0]
    b.values.push(function_ssa_value { id: 0, op: "const_int", block_id: 0, type_name: "int" }); f.blocks[0] = b; p.functions[0] = f
    if acceptance_expect("OperandID", verify_ssa_program(p), "duplicate value: sample.main") != 0 { return 7 }
    p = valid_program(); f = p.functions[0]; f.result_types = ["string"]; p.functions[0] = f
    if acceptance_expect("TypeMismatch", verify_ssa_program(p), "return type: sample.main") != 0 { return 8 }
    p = valid_program(); f = p.functions[0]; b = f.blocks[0]
    b.values.push(function_ssa_value { id: 1, op: "reference_get", operands: [0], block_id: 0, type_name: "int", symbol: "int" }); f.blocks[0] = b; p.functions[0] = f
    if acceptance_expect("InvalidReference", verify_ssa_program(p), "SSA reference operand referent type") != 0 { return 9 }
    p = branch_program(); f = p.functions[0]; b = f.blocks[1]; b.predecessors = int[](); f.blocks[1] = b; p.functions[0] = f
    if acceptance_expect("CFGEdge", verify_ssa_program(p), "inconsistent successor edge: sample.main") != 0 { return 10 }
    p = valid_program(); f = p.functions[0]; b = f.blocks[0]
    b.values.push(function_ssa_value { id: 1, op: "call", operands: [0], block_id: 0, type_name: "void" }); f.blocks[0] = b; p.functions[0] = f
    p.functions.push(function_ssa_function { symbol: "sample.external", parameter_types: ["string"], entry_block: -1, exit_block: -1 });
    p.calls.push(function_ssa_call { caller: "sample.main", callee: "sample.external", block_id: 0, value_id: 1 });
    if acceptance_expect("AMD64ABIcall", amd64_validate_program(p), "amd64: call argument type: sample.external") != 0 { return 11 }
    return 0
}
