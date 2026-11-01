#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-buildcfg.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.s" <<'S'
package main
extern "intrinsic" func buildcfg_goarch() string
func validate() () {
    if buildcfg_goarch() != "amd64" { panic("incorrect native architecture") }
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
p=Path(sys.argv[1]);lines=(p/'main.ir').read_text().splitlines()
for i,line in enumerate(lines):
 if line.startswith('CALL|') and '|buildcfg_goarch|0' in line:
  lines[i:i+1]=['ARG|42|_|_',line.replace('|buildcfg_goarch|0','|buildcfg_goarch|1')];break
else: raise AssertionError('architecture call missing')
(p/'bad.ir').write_text('\n'.join(lines)+'\n')
PY
printf preserve > "$work/output"
if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/bad.ir" "$work/output" > "$work/bad.log" 2>&1; then
    echo 'accepted invalid buildcfg argument' >&2; exit 1
fi
test "$(cat "$work/output")" = preserve
echo 'native architecture string contract and wrong arity rejection: PASS'
