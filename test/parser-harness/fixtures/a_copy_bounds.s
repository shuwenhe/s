package harness_copy_bounds
func main() int {
    source := alloc_array(int, 2);
    target := alloc_array(int, 1);
    copy_array(target, source, 2);
    return 0;
}
