package harness_array_record_use_after_move
struct Entry { int value }
func main() int {
    entries := alloc_array(Entry, 1);
    entry := Entry(42);
    entries[0] = entry;
    return entry.value;
}
