package harness_array_use_after_move
func main() int { values := alloc_array(int, 2); moved := values; return values[0]; }
