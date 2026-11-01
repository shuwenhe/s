#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage6-stable-identity.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage6-stable-identity.txt"
"$root/bin/s_compiler" declaration-ref-proof "$root/test/compiler/stage6_declaration_ref_basic.s" "$report"

grep -qx 'S6.1=PASS' "$report"
grep -qx 'S6.2=PASS' "$report"
grep -qx 'S6.3=PASS' "$report"
grep -qx 'S6.4=PASS' "$report"
grep -qx 'S6.4.same-candidate-equal=yes' "$report"
grep -qx 'S6.4.observation-count=2' "$report"
grep -qx 'S6.4.not-address-identity=yes' "$report"
grep -qx 'S6.4.evidence=canonical Stage 6 repeated construction from the same candidate yields the same DeclarationRef identity' "$report"

if grep -Eq 'S6\.5=PASS|S6\.6=PASS|same-spelling-different-package-distinct|distinct-canonical-identities' "$report"; then
  echo "S6.4 proof leaked later Stage 6 claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage6 stable identity proof self-test passed"
