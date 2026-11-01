package harness_array_drop_hook
struct Entry { int value }
func (Entry* self) drop() { println("drop"); }
func main() int {
    entries := alloc_array(Entry, 2);
    entries[0] = Entry(42);
    drop(entries);
    assert(live_allocations() == 0);
    return 0;
}
