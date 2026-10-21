package harness_alloc_drop_borrowed

func main() int {
    object := alloc(int);
    reference := &object;
    drop(object);
    return *reference;
}
