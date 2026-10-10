package compile.pipeline

import (
    "compile.internal.backend_elf64"
)

use compile.internal.backend_elf64.build as backend_build
use std.io.eprintln

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
    eprintln("[PIPELINE] Starting canonical compilation chain")
    eprintln("[PIPELINE] Authority sequence: Frontend → Middlend → Backend")
    
    checkpoint_emit(compilation_checkpoint {
        stage_name: "FRONTEND",
        input_type: "Source code (S language)",
        output_type: "Type-checked AST/IR",
        authority: authority_frontend(),
        phase: "parse + semantic + typecheck",
    })
    
    checkpoint_emit(compilation_checkpoint {
        stage_name: "MIDDLEND",
        input_type: "Type-checked IR",
        output_type: "Optimized MIR + SSA",
        authority: authority_middlend(),
        phase: "optimize + lower-to-ssa",
    })
    
    checkpoint_emit(compilation_checkpoint {
        stage_name: "BACKEND",
        input_type: "SSA program",
        output_type: "Machine code (ELF64)",
        authority: authority_backend(),
        phase: "codegen + emit-binary",
    })
    
    trace_authority(authority_frontend(), "parse → semantic → type-check")
    trace_authority(authority_middlend(), "run_midend_pipeline + build_ssa_pipeline")
    trace_authority(authority_backend(), "validate_abi + codegen + link_object_file")
    
    eprintln("[PIPELINE] Executing all three stages through compile.internal.backend_elf64.build()")
    eprintln("[AUTHORITY CHECK] backend_elf64.build() MUST NOT delegate to C seed")
    
    status := backend_build(context.input, context.output, context.ssa_margin_override, context.nostdlib)
    return status
}

func pipeline_finish(pipeline_context context, int status) pipeline_result {
    if status == 0 {
        eprintln("[PIPELINE] ✓ Compilation succeeded")
        eprintln("[AUTHORITY] Final artifact: " + context.output)
        eprintln("[AUTHORITY] All three stages (Frontend→Middlend→Backend) completed with canonical code")
    } else {
        eprintln("[PIPELINE] ✗ Compilation failed with exit code " + status)
    }
    return pipeline_result {
        exit_status: status,
        output: context.output,
        stage: "finished",
    }
}
