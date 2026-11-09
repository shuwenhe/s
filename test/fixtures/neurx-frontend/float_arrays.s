package neurx_frontend_probe
struct samples { []float values }
func scale([]float values, float factor) float {
    negative := -factor
    result := values[0] * factor + 1.25e-2
    if negative < 0.0 && result >= 0.0 { return result }
    return -2.5E+1
}
func main() int {
    empty := samples{values: []}
    values := []float{1.5, 2e0}
    values = append(values, float(3))
    allocated := make([]float, 2)
    return int(scale(values, float(2))) + byte(257)
}
