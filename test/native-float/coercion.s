package main
struct sample { float value }
func identity(float value) float { return value }
func zero() float { return 0 }
func final_zero() float { 0 }
func main() int {
    float local = 0
    if local != 0.0 { return 1 }
    local = 2
    local += 1.0
    if local != 3.0 { return 2 }
    record := sample { value: 2 }
    if record.value != identity(2) { return 3 }
    values := float[]{0, 2}
    values[0] = 1
    values.push(3)
    if values[0] != 1.0 || values[2] != 3.0 { return 4 }
    if zero() != 0.0 || final_zero() != 0.0 { return 5 }
    positive := 0.0
    negative := -positive
    if 1.0 / negative >= 0.0 { return 6 }
    return 0
}
