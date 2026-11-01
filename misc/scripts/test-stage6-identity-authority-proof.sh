#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage6-identity-authority.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage6-identity-authority.txt"
"$root/bin/s_compiler" declaration-ref-proof "$root/test/compiler/stage6_declaration_ref_basic.s" "$report"

grep -qx 'S6.1=PASS' "$report"
grep -qx 'S6.2=PASS' "$report"
grep -qx 'S6.3=PASS' "$report"
grep -qx 'S6.3.identity-authority=canonical' "$report"
grep -qx 'S6.3.independent-of-display-text=yes' "$report"
grep -qx 'S6.3.representation-prescribed=no' "$report"
grep -qx 'S6.3.evidence=canonical Stage 6 DeclarationRef carries identity independent of display text' "$report"

if grep -Eq 'S6\.5=PASS|S6\.6=PASS|distinct.*distinct|equal-canonical-identities' "$report"; then
  echo "S6.3 proof leaked later Stage 6 claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage6 identity authority proof self-test passed"
