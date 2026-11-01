#!/usr/bin/env bash
# Repeated eager array/record arguments must stay bounded as snapshots accumulate.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-runtime-snapshot.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
make -s -C "$root" seed-compiler-bin
cat > "$work/snapshot.s" <<'SRC'
struct snapshot_item { int number; int[] numbers }
func snapshot_sum(snapshot_item[] items) int {
    total := 0
    i := 0
    for i < len(items) {
        total = total + items[i].number + items[i].numbers[0]
        i = i + 1
    }
    return total
}
func main() int {
    items := snapshot_item[]()
    i := 0
    for i < 25 {
        next := i + 1
        items.push(snapshot_item { number: i, numbers: int[]{next} })
        i = i + 1
    }
    total := 0
    i = 0
    for i < 200 {
        total = total + snapshot_sum(items)
        i = i + 1
    }
    println(total)
    return 0
}
SRC
timeout 30s "$root/bin/s_seed" "$work/snapshot.s" "$work/snapshot.ir" > "$work/compile.log"
S_SOURCE_ROOT="$root" timeout 60s "$root/bin/s_seed" --emit-bin "$work/snapshot.ir" "$work/snapshot" >> "$work/compile.log"
status=0
timeout 10s "$work/snapshot" > "$work/output" || status=$?
if [[ "$status" -ne 0 ]]; then
    printf 'hosted record-array argument snapshots failed (status=%s)\n' "$status" >&2
    exit 1
fi
# Each pass sums 0..24 plus 1..25: 625; 200 passes total 125000.
if [[ "$(cat "$work/output")" != '125000' ]]; then
    cat "$work/output" >&2
    echo 'hosted record-array argument snapshots returned the wrong sum' >&2
    exit 1
fi

# Snapshot arguments before later writes and table growth. These IR operations
# make evaluation order explicit, including nested arrays of record aliases.
python3 - "$work/order.ir" <<'PY'
from pathlib import Path
import sys

lines = [
    'SSEED-TARGET-V1',
    'FUNC_BEGIN|main|_|_',
    'MOV|owner|"owner"|_',
    'MOV|owner.__type|"Record"|_',
    'MOV|owner.value|7|_',
    'MOV|owner.b|"owner.b"|_',
    'MOV|owner.b.__type|"Record"|_',
    'MOV|owner.b.value|11|_',
    'MOV|owner.bc.value|99|_',
    'MOV|child|"child"|_',
    'MOV|child.__type|"Record"|_',
    'MOV|child.value|13|_',
    'MOV|owner.items|[[child]]|_',
    'MOV|partc.value|1003|_',
    # Copying owner.b must not pick up the sibling prefix owner.bc.
    'MOV|part|owner.b|_',
    'ARG|owner|_|_',
    'ARG|owner.b|_|_',
    'ARG|owner.items|_|_',
    'MOV|owner.value|29|_',
    'MOV|owner.b.value|31|_',
    'MOV|child.value|37|_',
]
# Cross several table/index growth boundaries with the earlier ARGs pending.
lines.extend(f'MOV|fresh{i}.value|{i}|_' for i in range(300))
lines.extend([
    'ARG|0|_|_',
    'CALL|answer|read_snapshots|4',
    'ADD|total|answer|partc.value',
    'ARG|total|_|_',
    'CALL|printed|println|1',
    'RET|0|_|_',
    'FUNC_END|main|_|_',
    'FUNC_BEGIN|read_snapshots|_|_',
    'PARAM|record|_|_',
    'PARAM|inner|_|_',
    'PARAM|items|_|_',
    'PARAM|ignored|_|_',
    'ARG|items|_|_',
    'ARG|0|_|_',
    'CALL|row|__index_get|2',
    'ARG|row|_|_',
    'ARG|0|_|_',
    'CALL|element|__index_get|2',
    'ADD|sum|record.value|inner.value',
    'ADD|result|sum|element.value',
    'RET|result|_|_',
    'FUNC_END|read_snapshots|_|_',
])
Path(sys.argv[1]).write_text('\n'.join(lines) + '\n')
PY
S_SOURCE_ROOT="$root" timeout 60s "$root/bin/s_seed" --emit-bin "$work/order.ir" "$work/order" >> "$work/compile.log"
timeout 10s "$work/order" > "$work/order-output"
# Earlier arguments retain 7 + 11 + 13, and the neighboring prefix retains 1003.
if [[ "$(cat "$work/order-output")" != '1034' ]]; then
    cat "$work/order-output" >&2
    echo 'hosted nested record/array arguments lost their eager snapshots' >&2
    exit 1
fi
echo 'hosted runtime snapshot regression passed'
