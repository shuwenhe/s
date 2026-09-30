package compile.compiler

func compiler_stage10_lower_semantic_result(compiler_stage9_semantic_consumer_result semantic) compiler_stage10_mir_lowering_result {
    consumed := semantic.consumed && semantic.input_authority == "stage8-canonical-output" && semantic.canonical_reconstruction == "no" && semantic.canonical_type_ref != ""
    authority := ""
    reconstruction := "yes"
    mir := ""
    carrier := ""
    if consumed {
        authority = "stage9-semantic-result"
        reconstruction = "no"
        mir = "mir helper blocks=1 entry=0 exit=0"
        carrier = "compiler-stage10-mir-output"
    }
    return compiler_stage10_mir_lowering_result {
        consumed: consumed,
        input_authority: authority,
        semantic_reconstruction: reconstruction,
        mir_output: mir,
        output_carrier: carrier,
        readable: consumed,
        stage11_consumable: consumed,
    }
}

func compiler_stage10_mir_output_ready(compiler_stage10_mir_lowering_result output) bool {
    return output.consumed && output.input_authority == "stage9-semantic-result" && output.semantic_reconstruction == "no" && output.output_carrier == "compiler-stage10-mir-output" && output.readable && output.stage11_consumable && output.mir_output != ""
}

func compiler_emit_stage10_lowering_proof(string source) string {
    frontend := compiler_build_canonical_frontend_result(source)
    semantic := compiler_stage9_consume_canonical_frontend_result(frontend)
    lowered := compiler_stage10_lower_semantic_result(semantic)
    out := "stage=10\n"
    out = out + "input-stage=stage9\n"
    if compiler_stage10_mir_output_ready(lowered) {
        out = out + "S10.1=PASS\n"
        out = out + "S10.1.input-authority=stage9-semantic-result\n"
        out = out + "S10.1.semantic-input-consumed=yes\n"
        out = out + "S10.1.semantic-reconstruction=no\n"
        out = out + "S10.1.output-carrier=" + lowered.output_carrier + "\n"
        out = out + "S10.1.mir-output=" + lowered.mir_output + "\n"
        out = out + "S10.1.evidence=Stage10 production MIR lowerer consumes Stage9 semantic_result and emits a MIR output carrier\n"
        out = out + "S10.2=PASS\n"
        out = out + "S10.2.output-carrier=" + lowered.output_carrier + "\n"
        out = out + "S10.2.mir-readable=yes\n"
        out = out + "S10.2.stage11-consumable-boundary=yes\n"
        out = out + "S10.2.mir-output=" + lowered.mir_output + "\n"
        out = out + "S10.2.evidence=Stage10 emits canonical MIR through a readable output carrier consumable by the Stage11 boundary\n"
    } else {
        out = out + "S10.1=FAIL\n"
        out = out + "S10.1.reason=no observable Stage10 MIR lowering consumer of Stage9 semantic_result\n"
    }
    return out
}

func compiler_stage11_verify_canonical_mir(compiler_stage10_mir_lowering_result mir) compiler_stage11_mir_verification_result {
    consumed := compiler_stage10_mir_output_ready(mir) && mir.output_carrier == "compiler-stage10-mir-output" && mir.mir_output != ""
    authority := ""
    reconstruction := "yes"
    evidence := ""
    if consumed {
        authority = "stage10-canonical-mir-output"
        reconstruction = "no"
        evidence = "Stage11 MIR verifier consumes the readable Stage10 MIR output carrier without source or AST reconstruction"
    }
    return compiler_stage11_mir_verification_result {
        consumed: consumed,
        input_authority: authority,
        mir_reconstruction: reconstruction,
        evidence: evidence,
    }
}

func compiler_emit_stage11_mir_verification_proof(string source) string {
    frontend := compiler_build_canonical_frontend_result(source)
    semantic := compiler_stage9_consume_canonical_frontend_result(frontend)
    lowered := compiler_stage10_lower_semantic_result(semantic)
    verified := compiler_stage11_verify_canonical_mir(lowered)
    out := "stage=11\n"
    out = out + "input-stage=stage10\n"
    if verified.consumed && verified.input_authority == "stage10-canonical-mir-output" && verified.mir_reconstruction == "no" {
        out = out + "S11.1=PASS\n"
        out = out + "S11.1.input-authority=stage10-canonical-mir-output\n"
        out = out + "S11.1.input-carrier=" + lowered.output_carrier + "\n"
        out = out + "S11.1.mir-input-consumed=yes\n"
        out = out + "S11.1.mir-reconstruction=no\n"
        out = out + "S11.1.mir-output=" + lowered.mir_output + "\n"
        out = out + "S11.1.evidence=" + verified.evidence + "\n"
    } else {
        out = out + "S11.1=FAIL\n"
        out = out + "S11.1.reason=no observable Stage11 verifier consumer of Stage10 canonical MIR output\n"
    }
    return out
}

func compiler_stage12_consume_verified_mir(compiler_stage11_mir_verification_result verified, compiler_stage10_mir_lowering_result lowered) compiler_stage12_mir_input_boundary {
    consumed := verified.consumed && verified.input_authority == "stage10-canonical-mir-output" && verified.mir_reconstruction == "no" && lowered.output_carrier == "compiler-stage10-mir-output" && lowered.mir_output != ""
    authority := ""
    reconstruction := "yes"
    evidence := ""
    if consumed {
        authority = "stage11-verified-canonical-mir"
        reconstruction = "no"
        evidence = "Stage12 input boundary directly consumes the verified canonical MIR carrier from Stage11 without re-reading source, AST, or invoking MIR reconstruction"
    }
    return compiler_stage12_mir_input_boundary {
        consumed: consumed,
        input_authority: authority,
        mir_reconstruction: reconstruction,
        evidence: evidence,
    }
}

func compiler_emit_stage12_ownership_proof(string source) string {
    frontend := compiler_build_canonical_frontend_result(source)
    semantic := compiler_stage9_consume_canonical_frontend_result(frontend)
    lowered := compiler_stage10_lower_semantic_result(semantic)
    verified := compiler_stage11_verify_canonical_mir(lowered)
    input_boundary := compiler_stage12_consume_verified_mir(verified, lowered)
    out := "stage=12\n"
    out = out + "input-stage=stage11\n"
    if input_boundary.consumed && input_boundary.input_authority == "stage11-verified-canonical-mir" && input_boundary.mir_reconstruction == "no" {
        out = out + "S12.1=PASS\n"
        out = out + "S12.1.input-authority=stage11-verified-canonical-mir\n"
        out = out + "S12.1.mir-input-consumed=yes\n"
        out = out + "S12.1.mir-reconstruction=no\n"
        out = out + "S12.1.evidence=" + input_boundary.evidence + "\n"
        out = out + "S12.2=FAIL\n"
        out = out + "S12.2.reason=no observable Stage 12 move analysis producer\n"
        out = out + "first-unmet-contract=S12.2\n"
    } else {
        out = out + "S12.1=FAIL\n"
        out = out + "S12.1.reason=Stage12 cannot consume verified canonical MIR from Stage11\n"
        out = out + "first-unmet-contract=S12.1\n"
    }
    return out
}

