package std.prelude

struct box[t] {
    t value
}

func box[t](t value) box[t] {
    box[t] { value: value }
}

func len[t](t value) int32 {
    __runtime_len[t](value)
}

func to_string(int32 value) string {
    __int_to_string(value)
}

func char_at(string text, int32 index) string {
    __string_char_at(text, index)
}

func slice(string text, int32 start, int32 end) string {
    __string_slice(text, start, end)
}

extern "intrinsic" func __runtime_len[t](t value) int32

extern "intrinsic" func __int_to_string(int32 value) string

extern "intrinsic" func __string_char_at(string text, int32 index) string

extern "intrinsic" func __string_slice(string text, int32 start, int32 end) string
