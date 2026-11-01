#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-record-import.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/numbers.s" <<'S'
package numbers.types
struct cell { int number }
S
cat > "$work/strings.s" <<'S'
package strings.types
struct cell { string number }
S
cat > "$work/main.s" <<'S'
package main
import "numbers.types"
use numbers.types as numbers
struct wrapper { types.cell child; types.cell[] cells }
func bump(target* types.cell) { target.number = 42 }
func initialize(target* wrapper) { target.cells = make(types.cell[], 0) }
func clear(target* wrapper) { target.cells = types.cell[]() }
func fresh() numbers.cell { return numbers.cell {} }
func main() int {
    wrapped := wrapper {}
    initialize(wrapped)
    clear(wrapped)
    value := types.cell {}
    bump(value)
    return value.number + wrapped.child.number + text()
}
S
cat > "$work/text.s" <<'S'
package main
use strings.types as types
func text() int {
    made := fresh()
    if made.number != 0 { return 1 }
    value := types.cell { number: "types.cell" }
    if value.number == "types.cell" { return 0 }
    return 1
}
S
for order in first second; do
    clients=("$work/main.s" "$work/text.s")
    if [ "$order" = second ]; then clients=("$work/text.s" "$work/main.s"); fi
    "$root/bin/s_seed" --compile-native-unit "$work/$order.ir" "$work/numbers.s" "$work/strings.s" "${clients[@]}"
    grep -qF 'NOP|borrow-param:bump|target|numbers.types.cell' "$work/$order.ir"
    grep -qF 'NOP|record-field:main.wrapper|child|numbers.types.cell' "$work/$order.ir"
    grep -qF 'NOP|record-field:main.wrapper|cells|numbers.types.cell[]' "$work/$order.ir"
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$order.ir" "$work/$order"
    status=0; "$work/$order" || status=$?
    test "$status" -eq 42
done
# Import expansion must neither hide resource fields nor select the other file's
# copyable definition just because it has the same alias and record name.
cat > "$work/owners.s" <<'S'
package resources.types
struct cell { int* owner }
S
cat > "$work/owner.s" <<'S'
package main
import "resources.types"
func resource() int {
    value := types.cell {}
    return 0
}
S
printf 'preserve artifact\n' > "$work/output"
cp "$work/output" "$work/saved"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/numbers.s" "$work/owners.s" "$work/main.s" "$work/owner.s" > "$work/owner.log" 2>&1; then
    echo 'imported resource owner accepted' >&2; exit 1
fi
grep -q 'unsupported_owner' "$work/owner.log"
cmp "$work/output" "$work/saved"
cat > "$work/owner-array.s" <<'S'
package main
import "resources.types"
func main() int { values := make(types.cell[], 0); return len(values) + 42 }
S
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/owners.s" "$work/owner-array.s" > "$work/owner-array.log" 2>&1; then
    echo 'imported resource array accepted through make' >&2; exit 1
fi
grep -q 'unsupported_owner' "$work/owner-array.log"
cmp "$work/output" "$work/saved"
sed 's/make(types.cell\[\], 0)/types.cell[]()/' "$work/owner-array.s" > "$work/owner-constructor.s"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/owners.s" "$work/owner-constructor.s" > "$work/owner-constructor.log" 2>&1; then
    echo 'imported resource array accepted through typed constructor' >&2; exit 1
fi
grep -q 'unsupported_owner' "$work/owner-constructor.log"
cmp "$work/output" "$work/saved"
cat > "$work/ambiguous.s" <<'S'
package main
import "numbers.types"
import "strings.types"
func main() int { value := types.cell {}; return 42 }
S
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/numbers.s" "$work/strings.s" "$work/ambiguous.s" > "$work/ambiguous.log" 2>&1; then
    echo 'ambiguous type import accepted' >&2; exit 1
fi
grep -q 'ambiguous native type import' "$work/ambiguous.log"
cmp "$work/output" "$work/saved"
echo 'file-scoped imported record values, nested schemas, borrows and owner rejection: PASS'
