#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage6-uniqueness.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage6-uniqueness.txt"
S_STAGE6_UNIQUENESS_OTHER_INPUT="$root/test/compiler/stage6_declaration_ref_uniqueness_b.s" \
  "$root/bin/s_compiler" declaration-ref-proof "$root/test/compiler/stage6_declaration_ref_uniqueness_a.s" "$report"

grep -qx 'S6.1=PASS' "$report"
grep -qx 'S6.2=PASS' "$report"
grep -qx 'S6.3=PASS' "$report"
grep -qx 'S6.4=PASS' "$report"
grep -qx 'S6.5=PASS' "$report"
grep -qx 'S6.5.same-spelling-different-package-distinct=yes' "$report"
grep -qx 'S6.5.same-domain-distinct-declarations-distinct=yes' "$report"
grep -qx 'S6.5.kind-collision-distinguished=yes' "$report"
grep -qx 'S6.5.evidence=canonical Stage 6 distinct declarations produce distinct DeclarationRef identities' "$report"

if grep -Eq 'S7\.|Type Checking=PASS|CanonicalTypeRef=PASS|MIR=PASS|type-check-result=|canonical-type-ref=|mir-body=' "$report"; then
  echo "S6.5 proof leaked Stage 7 or later-stage output" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage6 uniqueness proof self-test passed"
