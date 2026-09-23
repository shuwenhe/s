package test

// Minimal struct definitions for testing member chains
type simple {
    value: int,
}

type with_array {
    items: simple[],
}

type nested {
    blocks: with_array[],
}

type with_member {
    target: simple,
}

type full_chain {
    edges: with_member[],
}

type full_nesting {
    terminator: full_chain,
}

type full_blocks {
    blocks: full_nesting[],
}

// LEVEL 1: Simple local variable
func test_level1() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    x := rewritten
}

// LEVEL 2: Single member access
func test_level2() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    x := rewritten.blocks
}

// LEVEL 3: Member + index
func test_level3() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    i := 0
    x := rewritten.blocks[i]
}

// LEVEL 4: Member + index + member
func test_level4() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    i := 0
    x := rewritten.blocks[i].terminator
}

// LEVEL 5: Full chain (member + index + member + member)
func test_level5() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    i := 0
    x := rewritten.blocks[i].terminator.edges
}

// LHS TEST 1: Assign to simple local
func test_lhs1() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    x := full_nesting { terminator: full_chain { edges: with_member[] () } }
    rewritten = x
}

// LHS TEST 2: Assign to member
func test_lhs2() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    x := full_nesting[] ()
    rewritten.blocks = x
}

// LHS TEST 3: Assign to member[index]
func test_lhs3() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    i := 0
    x := full_nesting { terminator: full_chain { edges: with_member[] () } }
    rewritten.blocks[i] = x
}

// LHS TEST 4: Assign to member[index].member
func test_lhs4() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    i := 0
    x := full_chain { edges: with_member[] () }
    rewritten.blocks[i].terminator = x
}

// LHS TEST 5: Assign to full chain (THE BLOCKER)
func test_lhs5() unit {
    rewritten := full_blocks { blocks: full_nesting[] () }
    i := 0
    x := with_member[] ()
    rewritten.blocks[i].terminator.edges = x
}
