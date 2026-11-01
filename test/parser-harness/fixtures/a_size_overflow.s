package harness_size_overflow
struct Entry { int first; int second; int third; int fourth }
func main() int { values := alloc_array(Entry, 999999999999999999); return 0; }
