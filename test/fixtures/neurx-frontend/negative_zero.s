package negative_zero_probe
func negate(float value) float { return -value }
func main() int {
    float zero = 0.0
    float negative = negate(zero)
    if 1.0 / negative < 0.0 { return 0 }
    return 1
}
