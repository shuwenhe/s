package bootstrap.closure
extern "intrinsic" func __host_byte_string(int value) string;
func identity(string value) string {
    return value
}

func main() {
    string value = identity(__host_byte_string(104))
    return len(value) + value[0] - 63
}
