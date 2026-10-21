package harness_array_noncopyable_copy
struct Entry { int value }
func (Entry* self) drop() { println("drop"); }
func main() int {
    first := alloc_array(Entry, 2);
    second := alloc_array(Entry, 2);
    copy_array(first, second, 2);
    return 0;
}
