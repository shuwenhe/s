package harness_alloc_owner_field

struct Holder { box value }

func main() int {
    object := alloc(Holder);
    return 0;
}
