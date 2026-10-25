package compile.internal
import (
    "compile.internal.syntax"
    "compile.internal.semantic"
    "compile.internal.ir.lower"
)

func canonical_source_to_mir(string source) mir_program_result {
    empty := mir_program { package_name: "", entry_symbol: "", functions: mir_program_function[](), calls: mir_program_call[](), enums: mir_program_enum[]() }
    trace := runtime_env_get("S_CANONICAL_TRACE", "") == "1"
    if trace { eprintln("canonical: parser begin") }
    parsed, parse_error := compile.internal.syntax.parse_source(source)
    if parse_error.message != "" { return mir_program_result { program: empty, error: "canonical parser:" + amd64_integer(parse_error.line) + ": " + parse_error.message } }
    if trace { eprintln("canonical: parser complete") }
    checked := compile.internal.semantic.check_source_file(parsed, source)
    if trace { eprintln("canonical: semantic complete") }
    if len(checked.errors) != 0 { return mir_program_result { program: empty, error: "canonical semantic: " + checked.errors[0].code + ": " + checked.errors[0].message } }
    lowered := compile.internal.ir.lower.lower_source_program(parsed)
    if trace { eprintln("canonical: MIR complete") }
    return lowered
}
