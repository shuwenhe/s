package demo.check

enum option[t] {
    some(t),
    none,
}

func unwrap_or_zero(option[int] value) int {
    switch value {
        some(inner) : inner,
        none : 0,
    }
}
