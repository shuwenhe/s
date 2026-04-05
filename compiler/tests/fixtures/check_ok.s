package demo.check

pub enum Option[T] {
    Some(T),
    None,
}

pub fn unwrap_or_zero(value: Option[i32]) -> i32 {
    match value {
        Some(inner) => inner,
        None => 0,
    }
}
