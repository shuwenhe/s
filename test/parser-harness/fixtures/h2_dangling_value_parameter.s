package harness_h2_dangling_value_parameter
func bad(int value) ref { return &value; }
func main() int { return 0; }
