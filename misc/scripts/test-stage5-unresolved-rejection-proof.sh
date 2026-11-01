#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage5-unresolved-rejection.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/unresolved_rejection.s" <<'SRC'
package stage5_unresolved_rejection

import (
    "std.io"
)

func helper() int {
    return 7;
}

func main() int {
    return missing();
}
SRC

make -C "$root" compiler >/dev/null

report="$work/stage5-unresolved-rejection.txt"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/unresolved_rejection.s" "$report"

grep -qx 'S5.1=PASS' "$report"
grep -qx 'S5.2=PASS' "$report"
grep -qx 'S5.3=PASS' "$report"
grep -qx 'S5.4=PASS' "$report"
grep -qx 'S5.8=PASS' "$report"
grep -qx 'S5.8.unresolved-name=missing' "$report"
grep -qx 'S5.8.rejection-source=canonical-compiler-function-lookup' "$report"
grep -qx 'S5.8.evidence=canonical Stage 5 unresolved-name rejection rejects missing function missing' "$report"

if grep -Eq '^S5\.9=PASS|DeclarationRef|CanonicalTypeRef|MIR' "$report"; then
  echo "S5.8 proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage5 unresolved-name rejection proof self-test passed"
