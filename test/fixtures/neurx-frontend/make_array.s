package make_array_probe
func main() int {
    float[] values = make([]float, 3)
    values[0] = 2.5
    if len(values) == 3 && values[0] == 2.5 { return 0 }
    return 1
}
