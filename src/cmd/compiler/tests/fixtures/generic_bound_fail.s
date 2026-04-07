package demo.generic

func require_copy[T: Copy](T value) T {
    value
}

func bad(String text) String {
    require_copy(text)
}
