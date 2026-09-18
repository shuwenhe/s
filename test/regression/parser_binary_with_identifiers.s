// Regression test for parser bug where binary operators with two identifier operands
// were incorrectly parsed as struct literals.
// See: looks_like_struct_literal heuristic accepting `:=` as field marker
// Bug: https://github.com/.../issues/... (parser bug in seed compiler)

func test_equal_identifiers() {
    a := 10
    b := 20
    if a == b {
        result := 0
    }
}

func test_not_equal_identifiers() {
    a := 10
    b := 20
    if a != b {
        result := 1
    }
}

func test_less_than_identifiers() {
    a := 10
    b := 20
    if a < b {
        result := 1
    }
}

func test_greater_than_identifiers() {
    a := 10
    b := 20
    if a > b {
        result := 0
    }
}

func test_less_equal_identifiers() {
    a := 10
    b := 20
    if a <= b {
        result := 1
    }
}

func test_greater_equal_identifiers() {
    a := 10
    b := 20
    if a >= b {
        result := 0
    }
}

func test_add_identifiers() {
    a := 10
    b := 20
    if a + b == 30 {
        result := 1
    }
}

func test_subtract_identifiers() {
    a := 20
    b := 10
    if a - b == 10 {
        result := 1
    }
}

func test_multiply_identifiers() {
    a := 10
    b := 2
    if a * b == 20 {
        result := 1
    }
}

func main() {
    test_equal_identifiers()
    test_not_equal_identifiers()
    test_less_than_identifiers()
    test_greater_than_identifiers()
    test_less_equal_identifiers()
    test_greater_equal_identifiers()
    test_add_identifiers()
    test_subtract_identifiers()
    test_multiply_identifiers()
}
