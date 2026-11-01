package audit
func pair() (int, int) { return 42, 7 }
func main() int { r := pair()
return r.0 + r.1 }
