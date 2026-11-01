package program_ir_adapter_contract_test

import (
    "compile.internal.ast"
    "compile.internal.ir.lower"
    "compile.internal.mir"
    "std"
    "std.option"
    "std.prelude"
)

func main() int {
    declaration := function_decl {
        sig: function_sig { name: "helper", generics: string[](), params: param[](), return_type: option[string].some("int") },
        body: option[block_expr].none, is_public: false,
    }
    signatures := mir_program_function[]()
    signatures = append(signatures, program_signature("sample", declaration))
    signatures = append(signatures, program_signature("lib", declaration))
    receiver := expr.name(name_expr { name: "lib", inferred_type: option[string].none })
    callee := expr.member(member_expr {
        target: std.prelude.box(receiver), member: "helper", inferred_type: option[string].none,
    })
    call := expr.call(call_expr {
        callee: std.prelude.box(callee), args: expr[](), inferred_type: option[string].none,
        resolved_callee: option[string].some("helper"), type_args: string[](),
    })
    state := program_lower_state {
        instructions: mir_program_instruction[](), binding_names: string[](), binding_values: int[](),
        next_value: 0, expression_value: -1, error: "",
    }
    lowered := program_lower_expression(call, "sample", signatures, state)
    if lowered.error != "" { return 1 }
    if len(lowered.instructions) != 1 { return 2 }
    if lowered.instructions[0].symbol != "lib.helper" { return 3 }

    declaration.sig.generics = string[]{"T"}
    signature := program_signature("sample", declaration)
    generic := program_lower_function("sample", declaration, signature, signatures)
    if generic.error != "generic function requires monomorphization: sample.helper" { return 4 }
    return 0
}
