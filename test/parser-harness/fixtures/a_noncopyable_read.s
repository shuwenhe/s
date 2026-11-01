package harness_array_noncopyable_read
struct Entry { int value }
func (Entry* self) drop() { println("drop"); }
func main() int { entries := alloc_array(Entry, 2); copied := entries[0]; return 0; }
