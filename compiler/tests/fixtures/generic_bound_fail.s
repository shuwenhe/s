package demo.generic

T require_copy[T: Copy](T value) {
    value
}

String bad(String text) {
    require_copy(text)
}
