#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-array-record-identity.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/valid.s" <<'S'
package main
struct entry { int value }
entries := entry[]()
func id[t](t value) t { return value }
func main() int {
    entries.push(entry { value: id(40) })
    entries.set(0, entry { value: 42 })
    entries[0] = entry { value: 42 }
    return entries[0].value
}
S
"$root/bin/s_seed" --compile-native-unit "$work/valid.ir" "$work/valid.s"
cat > "$work/library.s" <<'S'
package foreign
struct entry { int value }
S
python3 - "$work" <<'PYTEST'
from pathlib import Path
import sys
work=Path(sys.argv[1]); source=(work/'valid.s').read_text()
# Qualify the destination so rejection proves package identity even when both
# packages deliberately declare the same short record name and same fields.
source=source.replace('entries := entry[]()', 'entries := main.entry[]()')
for name,old,new in [
    ('push', 'entries.push(entry { value: id(40) })', 'entries.push(foreign.entry { value: id(40) })'),
    ('set', 'entries.set(0, entry { value: 42 })', 'entries.set(0, foreign.entry { value: 42 })'),
    ('index', 'entries[0] = entry { value: 42 }', 'entries[0] = foreign.entry { value: 42 }'),
]:
    (work/(name+'.s')).write_text(source.replace(old,new))
PYTEST
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
for name in push set index; do
    if "$root/bin/s_seed" --compile-native-unit "$work/output" "$work/library.s" "$work/$name.s" > "$work/$name.log" 2>&1; then
        echo "foreign record accepted by array $name" >&2; exit 1
    fi
    cmp "$work/output" "$work/saved"
    grep -q 'array element type mismatch' "$work/$name.log"
done
echo 'array record declaration identity and foreign type rejection: PASS'
