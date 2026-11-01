#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-mono-memory.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
python3 - "$work" <<'PY'
from pathlib import Path
import sys
work = Path(sys.argv[1])
source = 'package main\nfunc identity[t](t value) t { return value }\n'
source += ''.join(f'func f{i}(int value) int {{ return identity(value) }}\n' for i in range(1000))
source += 'func main(int input) int { return f999(input) + 41 }\n'
(work/'input.s').write_text(source)
PY
# The old traversal copied the complete AST with each mutable context and
# exhausted this bound before finishing the initial collection pass.
(ulimit -v 524288; timeout 60 "$compiler" --compile-unit "$work/program.sasm" "$work/input.s")
"$compiler" --emit-bin "$work/program.sasm" "$work/program"
status=0; "$work/program" 1 || status=$?
test "$status" -eq 42
echo '1000 generic callers compile within 512 MiB and execute: PASS'
