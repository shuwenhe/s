package test.runtime.generic_vec

func main() int {
    let values = vec[int]();
    values.push(11);
    values.push(22);
    if values.len() != 2 {
        return 1;
    }
    if values[0] + values[1] != 33 {
        return 2;
    }
    println("PASS: generic vec");
    return 0;
}
