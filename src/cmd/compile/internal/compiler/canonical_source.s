package compile.internal
import (
    "compile.internal.syntax"
    "compile.internal.semantic"
    "compile.internal.mono"
    "compile.internal.ir.lower"
)

func canonical_source_to_mir(string source) mir_program_result {
    empty := mir_program { package_name: "", entry_symbol: "", functions: mir_program_function[](), calls: mir_program_call[](), enums: mir_program_enum[]() }
    trace := runtime_env_get("S_CANONICAL_TRACE", "") == "1"
    if trace { eprintln("canonical: parser begin") }
    parsed, parse_error := compile.internal.syntax.parse_source(source)
    if parse_error.message != "" { return mir_program_result { program: empty, error: "canonical parser:" + amd64_integer(parse_error.line) + ": " + parse_error.message } }
    if trace { eprintln("canonical: parser complete") }
    checked := compile.internal.semantic.check_source_file_for_compile(parsed, source)
    if trace { eprintln("canonical: semantic complete") }
    if len(checked.errors) != 0 { return mir_program_result { program: empty, error: canonical_semantic_diagnostic(source, checked.errors[0]) } }
    annotated := compile.internal.mono.annotate_canonical_calls(parsed, checked, source)
    if annotated.error != "" { return mir_program_result { program: empty, error: "canonical annotation: " + annotated.error } }
    if trace { eprintln("canonical: semantic call annotation complete") }
    specialized := compile.internal.mono.monomorphize_file(annotated.file, checked)
    if specialized.error != "" { return mir_program_result { program: empty, error: "canonical monomorphization: " + specialized.error } }
    if specialized.invariant_errors != 0 { return mir_program_result { program: empty, error: "canonical monomorphization: unresolved generic function or call" } }
    if trace { eprintln("canonical: function specialization complete") }
    if trace { eprintln("canonical: type elaboration begin") }
    elaborated := compile.internal.mono.elaborate_generic_types(specialized.file)
    if elaborated.error != "" { return mir_program_result { program: empty, error: "canonical type elaboration: " + elaborated.error } }
    if trace { eprintln("canonical: type specialization complete") }
    if trace { eprintln("canonical: method lowering begin") }
    flattened := compile.internal.mono.flatten_canonical_methods(elaborated.file)
    if flattened.error != "" { return mir_program_result { program: empty, error: "canonical method lowering: " + flattened.error } }
    if trace { eprintln("canonical: MIR lowering begin") }
    lowered := compile.internal.ir.lower.lower_source_program(flattened.file)
    if trace { eprintln("canonical: MIR complete") }
    return lowered
}

func canonical_semantic_diagnostic(string source, compile.internal.semantic.semantic_error diagnostic) string {
    message := "canonical semantic:" + amd64_integer(diagnostic.line) + ":" + amd64_integer(diagnostic.column)
        + ": " + diagnostic.code + ": " + diagnostic.message
    if diagnostic.anchor != "" { message = message + " [anchor=" + diagnostic.anchor + "]" }
    context := canonical_source_line(source, diagnostic.line)
    if context != "" { message = message + "\n" + context }
    return message
}

func canonical_source_line(string source, int wanted_line) string {
    line := 1
    start := 0
    index := 0
    for index < len(source) {
        if __host_slice(source, index, index + 1) == "\n" {
            if line == wanted_line { return __host_slice(source, start, index) }
            line = line + 1
            start = index + 1
        }
        index = index + 1
    }
    if line == wanted_line { return __host_slice(source, start, len(source)) }
    return ""
}
