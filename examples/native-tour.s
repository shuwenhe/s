package main

struct Counter { int value }
struct Box[T] { T value }
enum Choice { some(int), none }

func identity[T](T value) T { return value }
func split(int value) (int, int) { return value / 10, value % 10 }
func (Counter* self) add(int amount) { self.value = self.value + amount }

func main() int {
    values := [4, 5, 6]
    saved := values
    values[0] = 40
    values.push(7)
    if saved[0] != 4 || len(saved) != 3 || len(values) != 4 { return 1 }

    counter := Counter { value: values[0] }
    counter.add(2)
    wrapped := Box[int] { value: identity(counter.value) }
    tens, units := split(wrapped.value)
    if tens != 4 || units != 2 { return 2 }

    selected := Choice.some(wrapped.value)
    return switch selected {
        Choice.some(value): value,
        Choice.none: 3,
    }
}
