package p2_probe_a
struct probe_value { int id }
func main() int {
    value := probe_value { id: 1 }
    if value.id != 1 { return 1 }
    return 0
}
