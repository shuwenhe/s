#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-reference-receiver.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
struct Cell[T] { T value }
struct Holder { Cell[int] cell }
func (Cell[T]* self) get() T { return self.value }
func (Cell[T]* self) set(T value) { self.value = value }
func (&Cell[int] self) read() int { return self.value }
func forward(Cell[int]* cell) int { return cell.get() }
func readonly(&Cell[int] cell) int { return cell.read() }
func main(int input) int {
    cell := Cell[int] { value: input }
    cell.set(40)
    holder := Holder { cell: Cell[int] { value: 2 } }
    return forward(cell*) + holder.cell.get() + readonly(&cell) - 40
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
for input in 1 7; do
    status=0; "$work/main" "$input" || status=$?
    test "$status" -eq 42
done
cat > "$work/result.s" <<'S'
package main
import "std.result"
struct Error { string message }
func good() result[int,Error] { return result.ok(42) }
func bad() result[int,Error] { return result.err(Error { message: "payload" }) }
func main(int input) int {
    value := good()
    if value.is_err() { return 1 }
    if input == 1 {
        failure := bad()
        if !failure.is_err() || failure.is_ok() { return 2 }
        return len(failure.unwrap_err().message) + 35
    }
    if input == 2 { ignored := value.unwrap_err(); return 3 }
    return value.unwrap()
}
S
"$compiler" --compile-unit "$work/result.sasm" "$work/result.s" "$root/src/result/result.s"
"$compiler" --emit-bin "$work/result.sasm" "$work/result"
for input in 0 1; do
    status=0; "$work/result" "$input" || status=$?
    test "$status" -eq 42
done
status=0; "$work/result" 2 > "$work/panic.log" 2>&1 || status=$?
test "$status" -eq 101
for body in 'return create().get()' 'return cell.combine(cell)' 'return cell.add(effect())'; do
    cat > "$work/invalid.s" <<S
package main
struct Cell { int value }
func (Cell* self) get() int { return self.value }
func (Cell* self) combine(Cell other) int { return self.value + other.value }
func (Cell* self) add(int value) int { return self.value + value }
func create() Cell { return Cell { value: 42 } }
func effect() int { return 1 }
func main() int { cell := create(); $body }
S
    printf preserve > "$work/rejected.sasm"
    if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/rejected.log" 2>&1; then
        echo 'unsafe reference receiver call accepted' >&2; exit 1
    fi
    grep -Eq 'canonical semantic:|overlapping borrowed call arguments|effectful argument after a borrow' "$work/rejected.log"
    test "$(cat "$work/rejected.sasm")" = preserve
done
echo 'native reference receivers: generic mutation, nested places, reborrows, result methods and strict rejection: PASS'
