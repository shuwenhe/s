package demo.generic

fn require_copy[T: Copy](value: T) -> T {
    value
}

fn bad(text: String) -> String {
    require_copy(text)
}
