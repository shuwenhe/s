package harness_alloc_unknown

func main() int {
    object := alloc(MissingType);
    return 0;
}
