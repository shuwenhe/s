package main
struct measurement { float value }
func twice(float x) float { return x * 2.0 }
func main() int {
    values := make([]float, 3)
    if len(values) != 3 { return 1 }
    if values[0] != 0.0 { return 2 }
    values[1] = 2.5
    m := measurement { value: values[1] }
    if twice(m.value) != 5.0 { return 3 }
    if 1 + m.value != 3.5 { return 4 }
    if m.value + 1 != 3.5 { return 5 }
    if byte(257) != 1 { return 6 }
    return 0
}
