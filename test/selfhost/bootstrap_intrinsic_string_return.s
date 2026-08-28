package bootstrap.closure

extern "intrinsic" func __host_slice(string value, int start, int end) string;

func identity(string value) string {
    return value
}

func main() {
    string value = identity(__host_slice("xhello", 1, 6))
    return len(value) + value[0] - 67
}
