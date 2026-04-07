package std.prelude

struct Box[T] {
    T value,
}

func box[T](T value) Box[T] {
    Box[T] { value: value }
}

func len[T](T value) i32 {
    __runtime_len[T](value)
}

func to_string(i32 value) String {
    __int_to_string(value)
}

func char_at(String text, i32 index) String {
    __string_char_at(text, index)
}

func slice(String text, i32 start, i32 end) String {
    __string_slice(text, start, end)
}

extern "intrinsic" func __runtime_len[T](T value) i32

extern "intrinsic" func __int_to_string(i32 value) String

extern "intrinsic" func __string_char_at(String text, i32 index) String

extern "intrinsic" func __string_slice(String text, i32 start, i32 end) String
