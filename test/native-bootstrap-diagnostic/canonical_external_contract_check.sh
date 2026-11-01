#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-external-contract.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.s" <<'S'
package main
extern "intrinsic" func __host_char_at(string text, int index) string
extern "intrinsic" func __host_char_at(string source, int offset) string
func main() int {
    if __host_char_at("ok", 0) == "o" { return 42 }
    return 7
}
S
"$compiler" --compile-unit "$work/program.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/program.sasm" "$work/program"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/program"
status=0; "$work/program" || status=$?
test "$status" -eq 42
for mode in result library body; do
    python3 - "$work" "$mode" <<'PY'
from pathlib import Path
import sys
work, mode = Path(sys.argv[1]), sys.argv[2]
source = (work / 'main.s').read_text()
old = 'extern "intrinsic" func __host_char_at(string source, int offset) string'
new = {
    'result': 'extern "intrinsic" func __host_char_at(string source, int offset) int',
    'library': 'extern "other" func __host_char_at(string source, int offset) string',
    'body': 'func __host_char_at(string source, int offset) string { return "o" }',
}[mode]
(work / 'bad.s').write_text(source.replace(old, new))
PY
    printf 'preserve artifact\n' > "$work/preserved.sasm"
    if "$compiler" --compile-unit "$work/preserved.sasm" "$work/bad.s" > "$work/reject.log" 2>&1; then
        echo "conflicting external contract accepted: $mode" >&2; exit 1
    fi
    test "$(cat "$work/preserved.sasm")" = 'preserve artifact'
done
echo 'matching external contract lowers once; conflicting contracts preserve rejection: PASS'
