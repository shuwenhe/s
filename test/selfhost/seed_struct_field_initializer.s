package main

struct inner {
    int value
}

struct Outer {
    int left
    inner inner
}

func make_outer() Outer {
    Outer {
        left: 1, inner inner {
            value: 2,
        },
    }
}
