#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-receiver.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
struct Pair[T] { T value }
struct Counter { int value }
func (Pair[T] self) get() T { return self.value }
func (Counter self) get() int { return self.value + 1 }
func main(int input) int {
    pair := Pair[int] { value: input }
    counter := Counter { value: 40 }
    return pair.get() + counter.get()
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
for input in 1 7; do
    status=0; "$work/main" "$input" || status=$?
    test "$status" -eq "$((input + 41))"
done
cat > "$work/left.s" <<'S'
package left
struct Pair[T] { T value }
func (Pair[T] self) get() T { return self.value }
S
cat > "$work/right.s" <<'S'
package right
struct Pair[T] { T value; int bias }
func (Pair[T] self) get() int { return self.bias }
S
cat > "$work/main.s" <<'S'
package main
import ("left"; "right")
func main(int input) int {
    first := left.Pair[int] { value: input }
    second := right.Pair[int] { value: 3, bias: 41 }
    return first.get() + second.get()
}
S
"$compiler" --compile-unit "$work/packages.sasm" "$work/main.s" "$work/right.s" "$work/left.s"
"$compiler" --emit-bin "$work/packages.sasm" "$work/packages"
for input in 1 7; do
    status=0; "$work/packages" "$input" || status=$?
    test "$status" -eq "$((input + 41))"
done
echo 'native generic and concrete receivers retain distinct nominal callees: PASS'
