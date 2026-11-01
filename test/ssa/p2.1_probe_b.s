package p2_probe_b
struct probe_value { int id }
func main() int {
    values := probe_value[]()
    values.push(probe_value { id: 1 })
    if values[0].id != 1 { return 1 }
    return 0
}
