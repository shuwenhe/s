#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-environment.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/constant.s" <<'S'
package main
const base = 40
func main() int { return base + 2 }
S
cat > "$work/global.s" <<'S'
package main
value := 40
func add() () { value = value + 2 }
func main() int { add(); return value }
S
cat > "$work/snapshot.s" <<'S'
package main
values := [40]
func main() int { saved := values; values[0] = 2; return saved[0] + values[0] }
S
cat > "$work/order.s" <<'S'
package main
answer := base + 2
base := 40
func main() int { return answer }
S
cat > "$work/shadow.s" <<'S'
package main
const base = 7
value := 11
func main() int { base := 40; value := 2; return base + value }
S
for name in constant global snapshot order shadow; do
    "$compiler" --compile-unit "$work/$name.sasm" "$work/$name.s"
    "$compiler" --emit-bin "$work/$name.sasm" "$work/$name"
    sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/$name"
    status=0; timeout 10 "$work/$name" || status=$?
    test "$status" -eq 42 || { echo "$name exit=$status expected=42" >&2; exit 1; }
done
for body in 'const base = 40; func main() int { base = 2; return base }' 'value := 40; func main() int { value = true; return 42 }' 'first := second; second := first; func main() int { return first }'; do
    printf 'package main\n%s\n' "$body" > "$work/invalid.s"
    printf keep > "$work/rejected.sasm"
    if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/rejected.log" 2>&1; then
        echo 'accepted invalid global/constant' >&2; exit 1
    fi
    test "$(cat "$work/rejected.sasm")" = keep
done
echo 'canonical constants/globals: initialization order, mutation, snapshots, lexical shadow and rejection: PASS'
