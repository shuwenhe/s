package harness_pointer
struct Cell { int value }
func set(Cell* cell, int value) { cell.value = value }
func read(ref Cell cell) int { return cell.value }
func forward(ref Cell cell) int { return read(cell) }
func main() int {
    cell := alloc(Cell)
    {
        view := &mut cell
        set(view, 19)
        assert(view.value == 19)
    }
    {
        view := &cell
        copy := view
        assert(forward(copy) == 19)
        assert(view.value == 19)
    }
    assert(cell.value == 19)
    drop(cell)
    assert(allocations() == 0)
    return 0
}
