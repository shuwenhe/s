#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-enum-identity.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/valid.s" <<'S'
package main
enum state { flag(bool), empty }
func id[t](t value) t { return value }
func take(state input) int { return id(42) }
func main() int {
    first := take(state.flag(false))
    second := take(main.state.empty)
    return first + second - 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/valid.ir" "$work/valid.s"
cat > "$work/scalar.s" <<'S'
package main
enum mode { empty, other }
func make_mode() mode { return mode.empty }
func modes() mode[] { item := mode.empty; return [item] }
func check(mode input) bool { return input == mode.empty }
func main() int {
    items := modes()
    if items[0] != mode.empty { return 1 }
    mode current = mode.empty
    current = mode.other
    assigned := (current = make_mode())
    if check(assigned) { return 42 }
    return 0
}
S
"$root/bin/s_seed" --compile-native-unit "$work/scalar.ir" "$work/scalar.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/scalar.ir" "$work/scalar"
status=0; timeout 15 "$work/scalar" || status=$?; test "$status" -eq 42
cat > "$work/foreign.s" <<'S'
package foreign
enum state { flag(bool), empty }
enum mode { empty, other }
S
# With no generic templates, ordinary checking must also retain local identity
# when another package declares the same enum name.
sed -e '/func id\[t\]/d' -e 's/return id(42)/return 42/' "$work/valid.s" > "$work/ordinary.s"
for order in first second; do
    sources=("$work/foreign.s" "$work/ordinary.s")
    if [ "$order" = second ]; then sources=("$work/ordinary.s" "$work/foreign.s"); fi
    "$root/bin/s_seed" --compile-native-unit "$work/ordinary-$order.ir" "${sources[@]}"
done
cat > "$work/pattern.s" <<'S'
package main
enum state { flag(bool), empty }
func main() int {
    value := state.flag(true)
    switch value {
        state::flag(flag): { if flag { return 42 } },
        state::empty: { return 1 },
    }
    return 0
}
S
for order in first second; do
    sources=("$work/foreign.s" "$work/pattern.s")
    if [ "$order" = second ]; then sources=("$work/pattern.s" "$work/foreign.s"); fi
    "$root/bin/s_seed" --compile-native-unit "$work/pattern-$order.ir" "${sources[@]}"
done
sed 's/take(state.flag(false))/take(foreign.state.flag(false))/' "$work/valid.s" > "$work/wrong.s"
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
for order in first second; do
    sources=("$work/foreign.s" "$work/wrong.s")
    if [ "$order" = second ]; then sources=("$work/wrong.s" "$work/foreign.s"); fi
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "${sources[@]}" > "$work/$order.log" 2>&1; then
        echo 'foreign enum accepted as local enum' >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
    grep -q 'type mismatch' "$work/$order.log"
done
python3 - "$work" <<'PYTEST'
from pathlib import Path
import sys
work=Path(sys.argv[1]); source=(work/'scalar.s').read_text()
for name,old,new in [
    ('return', 'return mode.empty', 'return foreign.mode.empty'),
    ('array-return', 'item := mode.empty', 'item := foreign.mode.empty'),
    ('compare', 'input == mode.empty', 'input == foreign.mode.empty'),
    ('initializer', 'mode current = mode.empty', 'mode current = foreign.mode.empty'),
    ('assign', 'current = mode.other', 'current = foreign.mode.other'),
    ('assign-expr', '(current = make_mode())', '(current = foreign.mode.empty)'),
]:
    (work/(name+'.s')).write_text(source.replace(old,new))
PYTEST
for name in return array-return compare initializer assign assign-expr; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/foreign.s" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "foreign enum accepted in $name" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
    grep -q 'type mismatch' "$work/$name.log"
done
echo 'enum constructor qualification and package identity: PASS'
