#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage5-import-registration.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/import_std_io.s" <<'SRC'
package cmd

import (
    "std.io"
)

func main() int {
    return 0
}
SRC

make -C "$root" compiler >/dev/null

report="$work/stage5-import-registration.txt"
"$root/bin/s_compiler" stage5-name-resolution-proof "$work/import_std_io.s" "$report"

grep -qx 'S5.1=PASS' "$report"
grep -qx 'S5.2=PASS' "$report"
grep -qx 'S5.3=PASS' "$report"
grep -qx 'S5.3.import-local-name=std' "$report"
grep -qx 'S5.3.import-package=std.io' "$report"
grep -qx 'S5.3.registration-source=canonical-stage5-input' "$report"
grep -qx 'S5.3.evidence=canonical Stage 5 import registration maps std to std.io' "$report"

if grep -Eq '^S5\.[4-9]=PASS|declaration-candidate|DeclarationRef|CanonicalTypeRef|MIR' "$report"; then
  echo "S5.3 proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage5 import registration proof self-test passed"
