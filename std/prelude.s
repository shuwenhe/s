package std.prelude

pub struct Box[T] {
    value: T,
}

pub fn box[T](value: T) -> Box[T] {
    Box[T] { value: value }
}

pub fn len[T](value: T) -> i32 {
    __runtime_len[T](value)
}

pub fn to_string(value: i32) -> String {
    __int_to_string(value)
}

pub fn char_at(text: String, index: i32) -> String {
    __string_char_at(text, index)
}

pub fn slice(text: String, start: i32, end: i32) -> String {
    __string_slice(text, start, end)
}

extern "intrinsic" fn __runtime_len[T](value: T) -> i32

extern "intrinsic" fn __int_to_string(value: i32) -> String

extern "intrinsic" fn __string_char_at(text: String, index: i32) -> String

extern "intrinsic" fn __string_slice(text: String, start: i32, end: i32) -> String
