// M1.1 DeclarationRef Vertical-Slice Proof
// 
// This test proves:
// 1. Semantic establishes DeclarationRef("demo", struct_kind, "Point")
// 2. DeclarationRef flows to Mono as value (not re-looked-up)
// 3. Mono work_item carries this ref without re-construction
//
// Proof mechanism:
// - check_source_file returns semantic_result.declarations[]
// - monomorphize_file receives this via parameter
// - mono_context stores declarations
// - mono_work_item populated from declarations
// - m1_identity_verification confirms ref is present and valid

struct Point {
    x: i32
    y: i32
}

func create_point_simple(i32 x, i32 y) Point {
    Point { x: x, y: y }
}

func main() {
    // This call will:
    // 1. Semantic: establish declaration_ref for "Point"
    // 2. Mono: receive this ref in mono_context.declarations
    // 3. Mono: populate mono_work_item.declaration_ref
    // 4. Verify: check that ref was NOT re-looked-up or re-constructed
    p := create_point_simple(i32(10), i32(20))
}
