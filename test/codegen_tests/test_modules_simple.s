package main
func test_emit_line_basic() int {
    1
}

func test_register_count() int {
    9
}

func test_stack_offset() int {
    -16
}

func main() int {
    int t1 = test_emit_line_basic()
    int t2 = test_register_count()
    int t3 = test_stack_offset()
    if t1 == 1 && t2 == 9 && t3 == -16 {
        0
    } else {
        1
    }
}
