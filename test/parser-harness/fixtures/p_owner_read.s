package harness_pointer
struct Cell { int value }
func main() int {
    cell := alloc(Cell)
    view := &mut cell
    assert(cell.value == 0)
    return view.value
}
