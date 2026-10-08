package compile.pipeline

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

