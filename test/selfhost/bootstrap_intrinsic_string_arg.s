package bootstrap.closure

extern "intrinsic" func __host_byte_at(string value, int index) int;

func main() {
    return __host_byte_at("hello", 0) - 62
}
