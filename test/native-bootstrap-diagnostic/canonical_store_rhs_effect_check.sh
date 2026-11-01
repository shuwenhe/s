#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-store-rhs-effect.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.s" <<'S'
package main
struct Cell { int cursor; int token }
struct Wrapper { Cell cell; int token }
func next(Cell* cell) int { cell.cursor = cell.cursor + 1; return 40 }
func fill(Cell* cell) { cell.token = next(cell) }
func main() int {
    owner := Cell {}
    owner.token = next(owner*)
    if owner.cursor != 1 || owner.token != 40 { return 1 }
    borrowed := Cell {}
    fill(borrowed*)
    if borrowed.cursor != 1 || borrowed.token != 40 { return 2 }
    nested := Wrapper {}
    nested.token = next(nested.cell*)
    if nested.cell.cursor != 1 || nested.token != 40 { return 3 }
    cells := Cell[]{Cell {}}
    cells[0].token = next(cells[0]*)
    if cells[0].cursor != 1 || cells[0].token != 40 { return 4 }
    compound := Cell { token: 2 }
    compound.token += next(compound*)
    if compound.cursor != 1 || compound.token != 42 { return 5 }
    return 42
}
S
cat > "$work/selector.s" <<'S'
package main
struct Cell { int cursor; int token }
struct Owner { Cell[] cells; int sibling }
calls := 0
owner := Owner { cells: Cell[]{Cell {}, Cell {}} }
func index() int { calls = calls + 1; owner.sibling = owner.sibling + 1; return 0 }
func rhs() int { owner.cells[0].cursor = owner.cells[0].cursor + 1; calls = calls + 10; return 40 }
func main() int {
    owner.cells[index()].token = rhs()
    if calls != 11 || owner.sibling != 1 { return 1 }
    if owner.cells[0].cursor != 1 || owner.cells[0].token != 40 { return 2 }
    if owner.cells[1].token != 0 { return 3 }
    return 42
}
S
for name in main selector; do
    "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
    "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
    status=0; timeout 10 "$work/$name" || status=$?
    test "$status" -eq 42 || { echo "store RHS mutation lost: $name exit=$status expected=42" >&2; exit 1; }
done
echo 'record, nested, borrowed, array, compound and global stores retain RHS mutations and evaluate selectors once: PASS'
