package ownership
func main() int {
    owner := box(20);
    {
        reference := &mut owner;
        *reference = *reference + 1;
    }
    moved := owner;
    {
        first := &moved;
        second := &moved;
        assert(*first == *second);
    }
    moved = box(*moved * 2);
    return *moved;
}
