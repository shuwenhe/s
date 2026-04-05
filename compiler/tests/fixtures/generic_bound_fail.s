package demo.generic

pub fn require_copy[T: Copy](value: T) -> T {
    value
}

pub fn bad(text: String) -> String {
    require_copy(text)
}
