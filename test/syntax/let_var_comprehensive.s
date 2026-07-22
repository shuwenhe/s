package main

func test_let_basics() void {
    let x = 42
    let message = "Hello, immutable world!"
    let arr = []int{1, 2, 3}
    println("Let variables created successfully")
}

func test_var_basics() void {
    var y = 99
    var text = "Mutable text"
    var nums = []int{10, 20, 30}

    y = 100
    text = "Updated text"
    nums = []int{40, 50, 60}
    println("Var variables reassigned successfully")
}

func test_typed_let() void {
    let count int = 5
    let flag bool = true
    let name string = "Alice"
    println("Typed let declarations work")
}

func test_typed_var() void {
    var counter int = 10
    var active bool = false
    var label string = "Label"

    counter = 20
    active = true
    label = "Updated label"
    println("Typed var declarations work")
}

func test_mixed() void {
    let constant = 100
    var mutable = 200

    mutable = 300
    println("Mixed let and var work together")
}

func test_var_loop() void {
    var i = 0
    var total = 0
    while i < 5 {
        total = total + i
        i = i + 1
    }
    println("Var in while loop works")
}

func main() int {
    test_let_basics()
    test_var_basics()
    test_typed_let()
    test_typed_var()
    test_mixed()
    test_var_loop()
    0
}
