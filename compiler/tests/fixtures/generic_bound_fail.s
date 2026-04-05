package demo.generic

func require_copy[T: Copy](value: T) -> T {
    value
}

func bad(text: String) -> String {
    require_copy(text)
}
