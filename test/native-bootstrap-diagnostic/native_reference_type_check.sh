#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-reference-type.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root, work = map(Path, sys.argv[1:])
source = (root/'src/cmd/compile/internal/mir/program.s').read_text()
start = source.index('func mir_program_contains_reference(')
end = source.index('\nfunc ', start + 1)
(work/'helper.s').write_text('package compile.internal\nextern "intrinsic" func __host_slice(string text, int start, int end) string\n' + source[start:end])
PY
cat > "$work/main.s" <<'S'
package compile.internal
func main() int {
    if !mir_program_contains_reference("&Widget") { return 1 }
    if !mir_program_contains_reference("[]&mutWidget") { return 2 }
    if !mir_program_contains_reference("(int,&Widget)") { return 3 }
    if mir_program_contains_reference("[]Widget") { return 4 }
    if mir_program_contains_reference("") { return 5 }
    return 0
}
S
"$root/bin/s_seed" --compile-native-unit "$work/check.ir" "$work/helper.s" "$work/main.s"
"$root/bin/s_seed" --emit-standalone-amd64 "$work/check.ir" "$work/check"
"$work/check"
echo 'native nested reference type detection: PASS'
