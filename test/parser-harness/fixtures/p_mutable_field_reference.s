package harness_pointer
struct Cell { int value }
func change(Cell* cell) {
    reference := &mut cell.value
    *reference = 42
    drop(reference)
}
func main() int { cell := alloc(Cell); change(cell); assert(cell.value == 42); return 0 }
