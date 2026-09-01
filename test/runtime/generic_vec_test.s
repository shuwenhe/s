package test.runtime.generic_vec
func main() {
    values := int[]();
    values = append(values, 11);
    values = append(values, 22);
    if len(values) != 2 {
        return 1;
    }
    if values[0] + values[1] != 33 {
        return 2;
    }
    println("PASS: generic vec");
    return 0;
}
