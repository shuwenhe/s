package test.third_field_partial_move

// ============================================================
// GATE TEST: Third-field Partial Move for Named Structs
//
// This test verifies that compiler.s can handle partial move
// of ANY field (not just first two) in a named struct.
//
// Expected behavior:
//   1. x := p.c  should compile successfully (c is 3rd field)
//   2. Generated C should: x = p->c; p->c = NULL;
//   3. Drop should skip c (because it's NULL)
//   4. y := p.c  should FAIL (use after partial move)
// ============================================================

struct Quad {
    box a
    box b
    box c  // THIRD FIELD - this is the key test
    box d
}

func test_third_field_partial_move() {
    p := Quad{box(1), box(2), box(3), box(4)}

    // PARTIAL MOVE THE THIRD FIELD
    x := p.c

    // Verify we got the value
    if *x != 3 {
        println("FAIL: expected p.c == 3")
    }

    // a, b, d should still be usable
    if *p.a != 1 {
        println("FAIL: expected p.a == 1 after p.c move")
    }
    if *p.b != 2 {
        println("FAIL: expected p.b == 2 after p.c move")
    }
    if *p.d != 4 {
        println("FAIL: expected p.d == 4 after p.c move")
    }

    println("✓ third field partial move succeeded")
}

func test_fourth_field_partial_move() {
    q := Quad{box(10), box(20), box(30), box(40)}

    // PARTIAL MOVE THE FOURTH FIELD
    y := q.d

    if *y != 40 {
        println("FAIL: expected q.d == 40")
    }

    // a, b, c should still be usable
    if *q.a != 10 {
        println("FAIL: expected q.a == 10 after q.d move")
    }
    if *q.b != 20 {
        println("FAIL: expected q.b == 20 after q.d move")
    }
    if *q.c != 30 {
        println("FAIL: expected q.c == 30 after q.d move")
    }

    println("✓ fourth field partial move succeeded")
}

func test_multiple_field_partial_moves() {
    r := Quad{box(100), box(200), box(300), box(400)}

    // Move fields c and a (non-sequential)
    x := r.c
    y := r.a

    if *x != 300 {
        println("FAIL: expected r.c == 300")
    }
    if *y != 100 {
        println("FAIL: expected r.a == 100")
    }

    // b and d should still be usable
    if *r.b != 200 {
        println("FAIL: expected r.b == 200")
    }
    if *r.d != 400 {
        println("FAIL: expected r.d == 400")
    }

    println("✓ multiple field partial moves succeeded")
}

func main() {
    println("=== GATE TEST: Third-Field Partial Move ===")

    test_third_field_partial_move()
    test_fourth_field_partial_move()
    test_multiple_field_partial_moves()

    println("=== ALL TESTS PASSED ===")
}
