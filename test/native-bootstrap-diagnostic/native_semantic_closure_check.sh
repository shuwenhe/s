#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-semantic-closure.XXXXXX)
trap 'rm -rf "$work"' EXIT
S_SOURCE_ROOT="$root" "$root/src/cmd/dist/source_closure.sh" src/cmd/compile/main.s "$work/sources"
python3 - "$work/sources" <<'PY'
from pathlib import Path
import sys
files=Path(sys.argv[1]).read_text().splitlines()
for name in ['src/cmd/compile/internal/semantic/semantic.s','src/cmd/compile/internal/stage5_gate.s','src/cmd/compile/internal/resolve/run_stage5_gate.s']:
 assert files.count(name)==1, 'missing or duplicated production semantic declaration: '+name
assert len(files)==len(set(files)), 'duplicate closure members'
assert not any(name.endswith('_test.s') or '/testdata/' in name for name in files), 'test source entered production closure'
PY
echo 'production semantic closure includes Stage5 declarations exactly once and excludes tests: PASS'
