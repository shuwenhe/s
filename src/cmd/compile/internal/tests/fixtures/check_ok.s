package demo.check

enum Option[T] {
    Some(T),
    None,
}

func unwrapOrZero(Option[int32] value) int32 {
    switch value {
        Some(inner) : inner,
        None : 0,
    }
}
