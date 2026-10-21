package harness_array_copy_type
struct First { int value }
struct Second { int value }
func main() int {
    first := alloc_array(First, 2);
    second := alloc_array(Second, 2);
    copy_array(first, second, 2);
    return 0;
}
