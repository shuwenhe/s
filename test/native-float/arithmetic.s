package main
func main() int {
    a := float(7)
    b := 2.5
    if a + b != 9.5 { return 1 }
    if a - b != 4.5 { return 2 }
    if a * b != 17.5 { return 3 }
    if a / b != 2.8 { return 4 }
    if int(b) != 2 { return 5 }
    values := float[]{a, b}
    if values[1] != b { return 6 }
    z := 0.0 / 0.0
    if z == z { return 7 }
    if z < b || z <= b || z > b || z >= b { return 8 }
    return 0
}
