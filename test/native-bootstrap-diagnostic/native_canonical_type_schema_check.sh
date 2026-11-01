#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-canonical-type-schema.XXXXXX)
trap 'rm -rf "$work"' EXIT
"$root/bin/s_seed" --dump-ast "$root/src/cmd/compile/internal/typesys/canonical_type.s" "$work/schema.ast"
python3 - "$work/schema.ast" <<'PY'
from pathlib import Path
import re,sys
text=Path(sys.argv[1]).read_text()
schema=text.split('name=canonical_type type=struct',1)[1].split('\n  FN_STMT',1)[0]
fields=re.findall(r'^      field=(.+)$',schema,re.M)
assert fields==['kind','primitive_name','declared_ref','child'], fields
PY
echo 'production canonical type parses four distinct named fields: PASS'
