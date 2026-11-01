#!/usr/bin/env bash
# Package state must be initialized once and shared across native calls.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-global-state.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "global state artifacts: $work" >&2; fi' EXIT
cat > "$work/main.s" <<'S'
package main
struct entry { string name }
entries := entry[]()
count := 2
func add(string name) () {
    if count == 2 { entries = append(entries, entry { name: name }) }
    else { entries.push(entry { name: name }) }
    count = count + 3
}
func local() int { count := 90; return count }
func snapshot() int[] { return [count] }
func main() int {
    args := host_args()
    if len(args) != 2 || args[1] != "global argument" { return 5 }
    add("first")
    add("second")
    if len(entries) != 2 { return 1 }
    if entries[0].name != "first" || entries[1].name != "second" { return 2 }
    if local() != 90 { return 3 }
    saved := snapshot()
    if saved[0] != 8 { return 4 }
    return count + 34
}
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" "global argument" || status=$?
test "$status" -eq 42
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
echo 'native package state initialization, mutation and local shadow: PASS'
cat > "$work/initializers.s" <<'S'
package main
first := initial()
text := "ok"
func initial() string { return text }
func combine() string { return first + text }
func main() int {
    if first != "ok" { return 1 }
    if combine() != "okok" { return 2 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/initializers.ir" "$work/initializers.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/initializers.ir" "$work/initializers"
status=0; "$work/initializers" || status=$?
test "$status" -eq 42
echo 'native transitive initializer order and global string arithmetic: PASS'
# Same-named package globals and parameter shadowing retain separate identities.
cat > "$work/left.s" <<'S'
package left
count := 11
func left_value() int { return count }
S
cat > "$work/right.s" <<'S'
package right
count := 31
func right_value() int { return count }
S
cat > "$work/packages.s" <<'S'
package main
import ( "left"; "right" )
func shadow(int count) int { return count }
func main() int { return left.left_value() + right.right_value() + shadow(0) }
S
for order in forward reverse; do
    sources=("$work/left.s" "$work/right.s" "$work/packages.s")
    if [ "$order" = reverse ]; then sources=("$work/packages.s" "$work/right.s" "$work/left.s"); fi
    "$root/bin/s_seed" --compile-native-unit "$work/packages-$order.ir" "${sources[@]}"
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/packages-$order.ir" "$work/packages-$order"
    status=0; "$work/packages-$order" || status=$?
    test "$status" -eq 42
done
# Forged descriptors and writes must be rejected before replacing output.
python3 - "$work" <<'PY'
import pathlib,sys
w=pathlib.Path(sys.argv[1]); text=(w/'main.ir').read_text()
slot=next(line.split('|')[1][12:] for line in text.splitlines() if line.startswith('NOP|global-slot:') and '|int|' in line)
line=next(line for line in text.splitlines() if line.startswith('NOP|global-slot:'+slot+'|'))
(w/'duplicate.ir').write_text(text+'\n'+line+'\n')
(w/'wrong-type.ir').write_text(text.replace(line,line.replace('|int|','|string|')))
(w/'inside-function.ir').write_text(text.replace('FUNC_BEGIN|main|_|_','FUNC_BEGIN|main|_|_\n'+line).replace(line+'\n','',1))
(w/'capture-local.ir').write_text(text.replace(slot,'count'))

(w/'wrong-write.ir').write_text(text.replace('MOV|'+slot+'|t', 'MOV|'+slot+'|"bad"|_\nNOP|unused|t',1))
# A cycle reached through helper calls is still an initializer cycle.
init=(w/'initializers.ir').read_text()
first=next(line.split('|')[1][12:] for line in init.splitlines() if line.startswith('NOP|global-slot:'))
(w/'cycle.ir').write_text(init.replace('RET|"ok"|_|_', 'RET|'+first+'|_|_'))
PY
printf 'preserve output\n' > "$work/preserve"
cp "$work/preserve" "$work/saved"
for bad in duplicate wrong-type wrong-write cycle inside-function capture-local; do
    if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$bad.ir" "$work/preserve" > "$work/$bad.log" 2>&1; then
        echo "accepted invalid native global IR: $bad" >&2; exit 1
    fi
    cmp "$work/preserve" "$work/saved"
done
echo 'native global package identity and forged IR rejection: PASS'
cat > "$work/project.s" <<'S'
package sample.state
struct state { int value }
shared := state { value: 17 }
S
cat > "$work/project-main.s" <<'S'
package main
use sample.state as other
func main() int { other.shared.value = other.shared.value + 8; return other.shared.value + 17 }
S
"$root/bin/s_seed" --compile-native-unit "$work/project.ir" "$work/project.s" "$work/project-main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/project.ir" "$work/project"
status=0; "$work/project" || status=$?
test "$status" -eq 42
echo 'native imported global record field read/write: PASS'
cat > "$work/vector-init.s" <<'S'
package main
first := initial()
entries := ["ready"]
func initial() int { return entries.len() }
func main() int { return first + 41 }
S
"$root/bin/s_seed" --compile-native-unit "$work/vector-init.ir" "$work/vector-init.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/vector-init.ir" "$work/vector-init"
status=0; "$work/vector-init" || status=$?
test "$status" -eq 42
echo 'native initializer dependency through vector receiver: PASS'

# Import aliases belong to each file, even for files in the same package.
cat > "$work/client-left.s" <<'S'
package main
use left as data
func one() int { return data.count }
S
cat > "$work/client-right.s" <<'S'
package main
use right as data
func two() int { return data.count }
func main() int { return one() + two() }
S
for order in forward reverse; do
    sources=("$work/client-left.s" "$work/client-right.s")
    if [ "$order" = reverse ]; then sources=("$work/client-right.s" "$work/client-left.s"); fi
    "$root/bin/s_seed" --compile-native-unit "$work/aliases-$order.ir" "$work/left.s" "$work/right.s" "${sources[@]}"
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/aliases-$order.ir" "$work/aliases-$order"
    status=0; "$work/aliases-$order" || status=$?
    test "$status" -eq 42
done
echo 'native globals retain file-local import aliases: PASS'
