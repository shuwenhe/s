package demo.matching

enum Option[T] {
    Some(T),
    None,
}

func unwrapOrZero(Option[int32] value) int32 {
    match value {
        Some(inner) => inner,
        None => 0,
    }
}
