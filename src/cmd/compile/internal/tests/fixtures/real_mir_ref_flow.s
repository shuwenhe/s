package demo.ownership_ref_flow

// This fixture tests real MIR ownership semantics extraction
// Expected flow:
//   P0: borrow(&owner, _2)
//   P1: ref_assign(_3, _2)  
//   P2: ref_use(_3)
//   P3: term

func test_ref_flow(int owner) int {
    reader := &owner
    other := reader
    x := *other
    x
}
