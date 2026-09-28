#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage5-unqualified-lookup.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/unqualified_lookup.s" <<'SRC'
package stage5_unqualified_lookup

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

report="$work/stage5-unqualified-lookup.txt"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/unqualified_lookup.s" "$report"

grep -qx 'S5.1=PASS' "$report"
grep -qx 'S5.2=PASS' "$report"
grep -qx 'S5.3=PASS' "$report"
grep -qx 'S5.4=PASS' "$report"
grep -qx 'S5.5=PASS' "$report"
grep -qx 'S5.5.lookup-name=helper' "$report"
grep -qx 'S5.5.lookup-package=stage5_unqualified_lookup' "$report"
grep -qx 'S5.5.lookup-kind=function' "$report"
grep -qx 'S5.5.lookup-source=canonical-compiler-find-func' "$report"
grep -qx 'S5.5.evidence=canonical Stage 5 unqualified lookup resolves helper to function helper in package stage5_unqualified_lookup' "$report"

if grep -Eq '^S5\.[78]=PASS|ambiguity|unresolved|DeclarationRef|CanonicalTypeRef|MIR' "$report"; then
  echo "S5.5 proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage5 unqualified lookup proof self-test passed"
