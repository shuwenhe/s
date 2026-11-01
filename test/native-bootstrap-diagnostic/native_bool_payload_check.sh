#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-bool-payload.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.s" <<'S'
package main
enum value { boolean(bool), number(int), }
func flag(value input) bool {
    switch input { value.boolean(item): item, value.number(_): false }
}
func validate() () {
    off := value.boolean(false)
    on := value.boolean(true)
    if flag(off) || !flag(on) { panic("wrong boolean payload") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
python3 - "$work" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=(p/'main.ir').read_text();assert '[false]' in s
for name,value in [('unknown','[missing]'),('string','["false"]')]:
 (p/(name+'.ir')).write_text(s.replace('[false]',value,1))
PY
for name in unknown string; do
 printf preserve > "$work/output"
 if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/$name.ir" "$work/output" > "$work/$name.log" 2>&1; then
    echo "accepted invalid boolean payload $name" >&2; exit 1
 fi
 test "$(cat "$work/output")" = preserve
done
echo 'native boolean payloads retain true/false values and reject unknown/string operands: PASS'
