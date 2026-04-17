package demo.matching

enum Option[T] {
    Some(T),
    None,
}

func unwrap_or_zero(Option[int32] value) int32 {
    switch value {
        Some(inner) : inner,
        None : 0,
    }
}
