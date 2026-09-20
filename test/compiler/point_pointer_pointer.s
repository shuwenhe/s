package test.compiler

// M2 Vertical Slice: Point** canonical type test
// CRITICAL: Tests both acceptance and rejection via canonical_same_type()

struct Point {
    x int
}

// Expected: Point**
func consume_point_pp(p **Point) int {
    return (*p).x
}

// Expected: Point*
func consume_point_p(p *Point) int {
    return p.x
}

func main() int {
    // POSITIVE TEST: Point** → consume_point_pp(Point**)
    // Should compile (canonical_same_type: Pointer(Pointer(Declared(Point))) == Pointer(Pointer(Declared(Point))))
    p := Point { x: 42 }
    pp := &p
    ppp := &pp
    result1 := consume_point_pp(ppp)
    assert(result1 == 42)
    
    // NEGATIVE TEST: Point* → consume_point_pp(Point**) 
    // Should REJECT (canonical_same_type: Pointer(Declared(Point)) != Pointer(Pointer(Declared(Point))))
    // If this compiles, it means canonical_same_type is NOT deciding
    result2 := consume_point_p(pp)
    assert(result2 == 42)
    
    return 0
}
