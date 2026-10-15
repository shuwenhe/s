package p2_probe_c
struct probe_block { int id; probe_value[] values }
struct probe_value { int id }
func main() int {
    values := probe_value[]()
    values.push(probe_value { id: 1 })
    block := probe_block { id: 0, values: values }
    if block.values[0].id != 1 { return 1 }
    return 0
}
