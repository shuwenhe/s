package harness_h2_dangling_local
func bad() ref {
    value := 42;
    return &value;
}
func main() int { return 0; }
