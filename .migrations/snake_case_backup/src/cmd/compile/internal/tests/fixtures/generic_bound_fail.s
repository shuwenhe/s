package demo.generic

func require_copy[T: Copy](T value) T {
    value
}

func bad(string text) string {
    require_copy(text)
}
