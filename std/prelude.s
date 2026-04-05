package std.prelude

struct Box[T] {
    value: T,
}

func box[T](value: T) -> Box[T] {
    Box[T] { value: value }
}

func len[T](value: T) -> i32 {
    __runtime_len[T](value)
}

func to_string(value: i32) -> String {
    __int_to_string(value)
}

func char_at(text: String, index: i32) -> String {
    __string_char_at(text, index)
}

func slice(text: String, start: i32, end: i32) -> String {
    __string_slice(text, start, end)
}

extern "intrinsic" func __runtime_len[T](value: T) -> i32

extern "intrinsic" func __int_to_string(value: i32) -> String

extern "intrinsic" func __string_char_at(text: String, index: i32) -> String

extern "intrinsic" func __string_slice(text: String, start: i32, end: i32) -> String
