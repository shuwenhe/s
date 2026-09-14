package main

struct Box[T] {
    value T
}

func (b Box[T]) get() T {
    b.value
}

func main() int {
    b := Box[int] { value: 42 }
    b.get()
}
