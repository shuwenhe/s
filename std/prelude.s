package std.prelude

pub struct Box[T] {
    value: T,
}

pub fn box[T](value: T) -> Box[T] {
    Box[T] { value: value }
}

pub fn len[T](value: T) -> i32 {
    0
}

pub fn to_string(value: i32) -> String {
    "<int>"
}

pub fn char_at(text: String, index: i32) -> String {
    "?"
}

pub fn slice(text: String, start: i32, end: i32) -> String {
    ""
}
