package compile.internal
import (
    "std"
)

func emit_canonical_mir_public(string source) string {
    return emit_canonical_mir(source)
}

func process_emit_mir(string source) string {
    return emit_canonical_mir_public(source)
}
