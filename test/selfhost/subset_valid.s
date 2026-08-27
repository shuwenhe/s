package selfhost.subset

const immutable_value := 5;

func main() {
    inferred := 10;
    inferred = 11;
    int explicit_value = 15;
    explicit_value = 20;
    return inferred + explicit_value + immutable_value;
}
