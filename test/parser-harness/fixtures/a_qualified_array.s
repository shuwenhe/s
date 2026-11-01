package harness_qualified_array
struct Entry { int value }
func main() int {
    entries := alloc_array(harness_qualified_array.Entry, 2);
    entries[0].value = 42;
    assert(entries[0].value == 42);
    entries = alloc_array(Entry, 1);
    assert(entries[0].value == 0);
    return 0;
}
