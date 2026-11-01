#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage5-ambiguity-rejection.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/ambiguity_rejection.s" <<'SRC'
package stage5_ambiguity_rejection

import (
    "std.io"
)

func helper() int {
    return 7;
}

func helper() int {
    return 8;
}

func main() int {
    return helper();
}
SRC

make -C "$root" compiler >/dev/null

report="$work/stage5-ambiguity-rejection.txt"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/ambiguity_rejection.s" "$report"

grep -qx 'S5.1=PASS' "$report"
grep -qx 'S5.2=PASS' "$report"
grep -qx 'S5.3=PASS' "$report"
grep -qx 'S5.4=PASS' "$report"
grep -qx 'S5.7=PASS' "$report"
grep -qx 'S5.7.ambiguous-name=helper' "$report"
grep -qx 'S5.7.candidate-kind=function' "$report"
grep -qx 'S5.7.rejection-source=canonical-compiler-function-index' "$report"
grep -qx 'S5.7.evidence=canonical Stage 5 ambiguity rejection rejects duplicate function helper' "$report"

if grep -Eq '^S5\.9=PASS|DeclarationRef|CanonicalTypeRef|MIR' "$report"; then
  echo "S5.7 proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage5 ambiguity rejection proof self-test passed"
