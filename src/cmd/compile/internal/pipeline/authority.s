package compile.internal.pipeline

use std.io.eprintln

struct authority_marker {
    string stage
    string module
    string checkpoint
    int timestamp
}

struct compilation_checkpoint {
    string stage_name
    string input_type
    string output_type
    authority_marker authority
    string phase
}

func authority_frontend() authority_marker {
    return authority_marker {
        stage: "frontend",
        module: "compile.compiler.native_source_to_mir",
        checkpoint: "Source → Structured function MIR",
        timestamp: 0,
    }
}

func authority_middlend() authority_marker {
    return authority_marker {
        stage: "middlend",
        module: "compile.internal.ssa.function_lower",
        checkpoint: "Function MIR → Verified function SSA",
        timestamp: 1,
    }
}

func authority_backend() authority_marker {
    return authority_marker {
        stage: "backend",
        module: "compile.internal.codegen.amd64_program + GNU as/ld",
        checkpoint: "Function SSA → amd64 instructions → ELF",
        timestamp: 2,
    }
}

func trace_authority(authority_marker marker, string detail) {
    if detail != "" {
        eprintln("[" + marker.stage + "] authority=" + marker.module + " | " + detail)
    }
}

func checkpoint_emit(compilation_checkpoint cp) {
    eprintln("[ CHECKPOINT ] " + cp.stage_name + 
             " | input=" + cp.input_type + 
             " | output=" + cp.output_type + 
             " | authority=" + cp.authority.module)
}
