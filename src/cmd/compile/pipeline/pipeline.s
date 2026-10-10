package compile.pipeline

import (
    "compile.internal.backend_elf64"
)

use compile.internal.backend_elf64.build as backend_build

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
    return backend_build(context.input, context.output, context.ssa_margin_override, context.nostdlib)
}

func pipeline_finish(pipeline_context context, int status) pipeline_result {
    return pipeline_result {
        exit_status: status,
        output: context.output,
        stage: "finished",
    }
}
