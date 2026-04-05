package demo.matching

enum Option[T] {
    Some(T),
    None,
}

func unwrap_or_zero(value: Option[i32]) -> i32 {
    match value {
        Some(inner) => inner,
        None => 0,
    }
}
