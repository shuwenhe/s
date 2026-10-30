#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-mono-index-scaling.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$work/input.s" <<'PY'
from pathlib import Path
import sys
source = 'package main\n'
for record in range(200):
    source += f'struct Record{record} {{ ' + '; '.join(f'int field{field}' for field in range(20)) + ' }\n'
body = 'value = value + 0; ' * 20 + 'return identity(value)'
source += ''.join(f'func f{i}(int value) int {{ {body} }}\n' for i in range(1000))
source += 'func identity[T](T value) T { return value }\n'
source += 'func main(int input) int { return f999(input) + 41 }\n'
Path(sys.argv[1]).write_text(source)
PY
(ulimit -v 2097152; timeout 120 "$compiler" --compile-unit "$work/main.sasm" "$work/input.s")
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" 1 || status=$?
test "$status" -eq 42
echo 'indexed specialization handles 4000 fields and 1000 late generic callers within 2 GiB/120 seconds: PASS'
