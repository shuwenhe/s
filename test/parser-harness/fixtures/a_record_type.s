package harness_array_record_type
struct First { int value }
struct Second { int value }
func main() int { values := alloc_array(First, 2); values[0] = Second(42); return 0; }
