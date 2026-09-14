package demo.ownership_ref_flow
// This fixture tests real MIR ownership semantics extraction
// Verifies semantic point ordering with interleaved regular statements
// Expected ownership order:
//   Pb: borrow(&owner)       statement 1
//   Pa: ref_assign(other)    statement 3
//   Pu: ref_use(x)           statement 5
func test_ref_flow(int owner) int {
    reader := &owner       // stmt 1: ownership::Borrow -> Pb
    y := 100               // stmt 2: regular eval (no ownership)
    other := reader        // stmt 3: ownership::RefAssign -> Pa
    z := y + 1             // stmt 4: regular eval (no ownership)
    x := *other            // stmt 5: ownership::RefUse -> Pu
