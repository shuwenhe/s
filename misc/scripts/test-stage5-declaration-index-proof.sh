#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage5-declaration-index.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/declaration_index.s" <<'SRC'
package stage5_declaration_index

import (
    "std.io"
)

func helper() int {
    return 7;
}

func main() int {
    return 0;
}
SRC

make -C "$root" compiler >/dev/null

report="$work/stage5-declaration-index.txt"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/declaration_index.s" "$report"

grep -qx 'S5.1=PASS' "$report"
grep -qx 'S5.2=PASS' "$report"
grep -qx 'S5.3=PASS' "$report"
grep -qx 'S5.4=PASS' "$report"
grep -qx 'S5.4.declaration-count=1' "$report"
grep -qx 'S5.4.declaration.0.package=stage5_declaration_index' "$report"
grep -qx 'S5.4.declaration.0.name=helper' "$report"
grep -qx 'S5.4.declaration.0.kind=function' "$report"
grep -qx 'S5.4.index-source=canonical-compiler-function-index' "$report"
grep -qx 'S5.4.evidence=canonical Stage 5 declaration index contains function helper in package stage5_declaration_index' "$report"

if grep -Eq '^S5\.[5-9]=PASS|DeclarationRef|CanonicalTypeRef|MIR' "$report"; then
  echo "S5.4 proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage5 declaration index proof self-test passed"
