package std.result

pub enum Result[T, E] {
    Ok(T),
    Err(E),
}
