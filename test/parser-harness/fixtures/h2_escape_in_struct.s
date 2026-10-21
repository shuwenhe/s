package harness_h2_escape_in_struct
struct Holder { ref saved }
func main() int {
    value := 42;
    holder := Holder(&value);
    return 0;
}
