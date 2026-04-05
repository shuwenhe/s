package demo.matching

enum Option[T] {
    Some(T),
    None,
}

i32 unwrap_or_zero(Option[i32] value){
    match value {
        Some(inner) => inner,
        None => 0,
    }
}
