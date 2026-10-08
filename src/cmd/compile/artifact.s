package compile.pipeline

// Canonical pipeline invariant:
//
// A stage may consume only:
//   1. the canonical artifact produced by its immediate predecessor, or
//   2. immutable earlier-stage context explicitly declared in the transition
//      contract.
//
// A stage must not reconstruct its input by:
//   - reparsing source
//   - rescanning source text
//   - parsing proof output
//   - re-resolving names
//   - rebuilding semantic facts owned by an earlier stage
//
// Artifacts are compiler facts.
// Proof output is an observation of facts for gates, audits, and humans.
// Proof output must never be a semantic input to another compiler stage.

struct artifact_kind {
    string name
}

struct source_artifact {
    string source_path
}

struct token_artifact {
    string source_path
}

struct ast_artifact {
    string source_path
}

struct resolved_names_artifact {
    string source_path
}

struct declaration_ref_artifact {
    string source_path
}

struct type_facts_artifact {
    string source_path
}

struct canonical_type_ref_artifact {
    string source_path
}

struct semantic_artifact {
    string source_path
}

struct mir_artifact {
    string source_path
}

struct verified_mir_artifact {
    string source_path
}

struct ownership_facts_artifact {
    string source_path
}

struct monomorphized_artifact {
    string source_path
}

struct layout_artifact {
    string source_path
}

struct abi_artifact {
    string source_path
}

struct codegen_artifact {
    string source_path
}

struct object_artifact {
    string source_path
}

