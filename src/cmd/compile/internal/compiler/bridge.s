package compile.internal.compiler

import (
    "compile.internal.syntax"
    "compile.internal.semantic"
    "compile.internal.ir.lower"
    "compile.internal.mir"
)

func emit_canonical_mir(string source) string {
    parse_result := compile.internal.syntax.parse_source(source)
    parsed := parse_result.0
    parse_err := parse_result.1
    if parse_err.message != "" {
        return "mir-error: parse " + parse_err.message + "\n"
    }
    
    semantic_result := compile.internal.semantic.check_source_file(parsed, source)
    if len(semantic_result.errors) > 0 {
        error := semantic_result.errors[0]
        return "mir-error: semantic " + error.code + ": " + error.message + "\n"
    }
    
    lower_result := compile.internal.ir.lower.lower_main_to_mir(parsed)
    graph := lower_result.0
    lowering_err := lower_result.1
    if lowering_err != "" {
        return "mir-error: lowering " + lowering_err + "\n"
    }
    
    return compile.internal.mir.dump_graph(graph) + "\n"
}
