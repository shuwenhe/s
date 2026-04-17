package demo.generic

func requireCopy[T: Copy](T value) T {
    value
}

func bad(string text) string {
    requireCopy(text)
}
