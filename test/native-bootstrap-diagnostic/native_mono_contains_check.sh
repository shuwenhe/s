#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-mono-contains.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root, work = map(Path, sys.argv[1:])
source = (root/'src/cmd/compile/internal/mono/monomorphization.s').read_text()
start = source.index('func mono_contains_text(')
(work/'helper.s').write_text('package compile.internal.mono\nimport "std.prelude"\n' + source[start:])
PY
cat > "$work/main.s" <<'S'
package main
import "compile.internal.mono"
func main() int {
    if !compile.internal.mono.mono_contains_text("identity__mono_int", "__mono") { return 1 }
    if !compile.internal.mono.mono_contains_text("__mono", "__mono") { return 2 }
    if compile.internal.mono.mono_contains_text("identity", "__mono") { return 3 }
    if compile.internal.mono.mono_contains_text("", "__mono") { return 4 }
    if !compile.internal.mono.mono_contains_text("identity", "") { return 5 }
    return 0
}
S
"$root/bin/s_seed" --compile-native-unit "$work/check.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$work/helper.s" "$work/main.s"
"$root/bin/s_seed" --emit-standalone-amd64 "$work/check.ir" "$work/check"
"$work/check"
echo 'S monomorphization substring matching: PASS'
