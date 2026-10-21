package harness_bounds_write
struct Entry { int value }
func main() int { values := alloc_array(Entry, 2); values[-1].value = 42; return 0; }
