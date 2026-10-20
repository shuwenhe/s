package compile.internal



struct pipeline_context {
    string input
    string output
    string ssa_margin_override
    bool nostdlib
    string stage
}

struct pipeline_result {
    int exit_status
    string output
    string stage
}

func pipeline_build(string input, string output, string ssa_margin_override, bool nostdlib) int {
    context := pipeline_prepare(input, output, ssa_margin_override, nostdlib)
    status := pipeline_compile(context)
    result := pipeline_finish(context, status)
    return result.exit_status
}

func pipeline_prepare(string input, string output, string ssa_margin_override, bool nostdlib) pipeline_context {
    return pipeline_context {
        input: input,
        output: output,
        ssa_margin_override: ssa_margin_override,
        nostdlib: nostdlib,
        stage: "prepared",
    }
}

func pipeline_compile(pipeline_context context) int {
    eprintln("[PIPELINE] Function MIR → SSA → amd64 instructions → ELF")
    
    checkpoint_emit(compilation_checkpoint {
        stage_name: "FRONTEND",
        input_type: "Source code (S language)",
        output_type: "Structured function MIR",
        authority: authority_frontend(),
        phase: "parse + signatures + function bodies",
    })
    
    checkpoint_emit(compilation_checkpoint {
        stage_name: "MIDDLEND",
        input_type: "Structured function MIR",
        output_type: "Structured function SSA",
        authority: authority_middlend(),
        phase: "verify-mir + lower-to-ssa + verify-ssa",
    })
    
    checkpoint_emit(compilation_checkpoint {
        stage_name: "BACKEND",
        input_type: "SSA program",
        output_type: "Machine code (ELF64)",
        authority: authority_backend(),
        phase: "codegen + emit-binary",
    })
    
    trace_authority(authority_frontend(), "native_source_to_mir")
    trace_authority(authority_middlend(), "lower_function_mir_to_ssa")
    trace_authority(authority_backend(), "emit_function_ssa_amd64 + as + ld")
    status := native_build(context.input, context.output, context.ssa_margin_override, context.nostdlib)
    return status
}

func pipeline_finish(pipeline_context context, int status) pipeline_result {
    if status == 0 {
        eprintln("[PIPELINE] ✓ Compilation succeeded")
        eprintln("[AUTHORITY] Final artifact: " + context.output)
        eprintln("[AUTHORITY] Function MIR/SSA native compilation completed")
    } else {
        eprintln("[PIPELINE] ✗ Compilation failed")
    }
    return pipeline_result {
        exit_status: status,
        output: context.output,
        stage: "finished",
    }
}
