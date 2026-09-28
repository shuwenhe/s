#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage5-qualified-lookup.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/qualified_lookup.s" <<'SRC'
package stage5_qualified_lookup

import (
    "std.io"
)

func helper() int {
    return 7;
}

func main() int {
    return helper();
}
SRC

make -C "$root" compiler >/dev/null

report="$work/stage5-qualified-lookup.txt"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/qualified_lookup.s" "$report"

grep -qx 'S5.1=PASS' "$report"
grep -qx 'S5.2=PASS' "$report"
grep -qx 'S5.3=PASS' "$report"
grep -qx 'S5.4=PASS' "$report"
grep -qx 'S5.5=PASS' "$report"
grep -qx 'S5.6=PASS' "$report"
grep -qx 'S5.6.lookup-package=stage5_qualified_lookup' "$report"
grep -qx 'S5.6.lookup-name=helper' "$report"
grep -qx 'S5.6.lookup-kind=function' "$report"
grep -qx 'S5.6.lookup-source=canonical-qualified-function-index' "$report"
grep -qx 'S5.6.evidence=canonical Stage 5 qualified lookup resolves stage5_qualified_lookup.helper to function helper' "$report"

if grep -Eq 'unresolved|DeclarationRef|CanonicalTypeRef|MIR' "$report"; then
  echo "S5.6 proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage5 qualified lookup proof self-test passed"
