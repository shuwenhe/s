#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-source-reader.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/read.s" <<'S'
package main
extern "intrinsic" func __host_read_source(string path) string
func read_source(string path) string { return "wrong binding" }
func main() int {
    args := host_args()
    text := __host_read_source(args[1])
    if text == "data" { return 42 }
    if text == "" { return 7 }
    if len(text) == 16777216 { return 43 }
    return 99
}
S
"$root/bin/s_seed" "$work/read.s" "$work/read.ir"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/read.ir" "$work/read"
python3 - "$work" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
(p / 'valid').write_bytes(b'data')
(p / 'nul').write_bytes(b'da\0ta')
(p / 'limit').write_bytes(b' ' * 16777216)
(p / 'oversize').write_bytes(b' ' * 16777216 + b'\0')
PY
for pair in 'valid 42' 'nul 7' 'limit 43' 'oversize 7' 'missing 7'; do
    read -r name wanted <<< "$pair"
    status=0; "$work/read" "$work/$name" || status=$?
    if [ "$status" -ne "$wanted" ]; then
        echo "source reader $name: expected $wanted, got $status" >&2; exit 1
    fi
done
echo 'native source reader, intrinsic binding, NUL and capacity checks: PASS'
