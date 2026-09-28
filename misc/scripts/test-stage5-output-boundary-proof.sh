#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage5-output-boundary.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/output_boundary.s" <<'SRC'
package stage5_output_boundary

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

report="$work/stage5-output-boundary.txt"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/output_boundary.s" "$report"

grep -qx 'S5.1=PASS' "$report"
grep -qx 'S5.2=PASS' "$report"
grep -qx 'S5.3=PASS' "$report"
grep -qx 'S5.4=PASS' "$report"
grep -qx 'S5.5=PASS' "$report"
grep -qx 'S5.6=PASS' "$report"
grep -qx 'S5.9=PASS' "$report"
grep -qx 'S5.9.output-kind=resolved-declaration-candidate' "$report"
grep -qx 'S5.9.candidate-package=stage5_output_boundary' "$report"
grep -qx 'S5.9.candidate-name=helper' "$report"
grep -qx 'S5.9.candidate-kind=function' "$report"
grep -qx 'S5.9.boundary-source=canonical-stage5-name-resolution-proof' "$report"
grep -qx 'S5.9.next-stage-input=declaration-candidate' "$report"
grep -qx 'S5.9.no-declaration-ref=yes' "$report"
grep -qx 'S5.9.evidence=canonical Stage 5 output boundary exposes resolved declaration candidate stage5_output_boundary.helper without later-stage identity' "$report"

if grep -Eq 'DeclarationRef|CanonicalTypeRef|MIR' "$report"; then
  echo "S5.9 proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage5 output boundary proof self-test passed"
