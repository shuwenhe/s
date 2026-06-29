package main

func test_let_reassign_error() void {
    let x = 10
    x = 20  // This should cause an error
}

func main() int {
    test_let_reassign_error()
    0
}
