package demo.matching

enum option[t] {
    some(t),
    none,
}

func unwrap_or_zero(option[int32] value) int32 {
    switch value {
        some(inner) : inner,
        none : 0,
    }
}
