package demo.check

enum Option[T] {
    Some(T),
    None,
}

func unwrap_or_zero(Option[i32] value) i32 {
    match value {
        Some(inner) => inner,
        None => 0,
    }
}
