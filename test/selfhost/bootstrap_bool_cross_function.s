package bootstrap.closure
func is_large(int value) bool {
    return value > 10
}

func identity(bool value) bool {
    return value
}

func main() {
    if identity(is_large(20)) {
        return 42
    }
    return 1
}
