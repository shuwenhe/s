package compile.internal

import (
    "compile.internal.parser.syntax"
    "compile.internal.semantic"
)

func CanonicalAstCheck(string source) string {
    parsed, parse_err := syntax.parse_source(source)
    if parse_err.message != "" {
        return "canonical-ast-error: parse " + parse_err.message
    }
    semantic_result := compile.internal.semantic.check_source_file(parsed, source)
    if len(semantic_result.errors) > 0 {
        error := semantic_result.errors[0]
        return "canonical-ast-error: semantic " + error.code + ": " + error.message
    }
    return "canonical-ast package=" + parsed.pkg + " source_file=canonical semantic=checked"
}
