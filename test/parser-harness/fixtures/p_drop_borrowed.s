package harness_pointer
struct Cell { int value }
func main() int {
    cell := alloc(Cell)
    view := &mut cell
    drop(cell)
    return view.value
}
