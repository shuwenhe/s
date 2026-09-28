#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage6-output-boundary.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage6-output-boundary.txt"
S_STAGE6_UNIQUENESS_OTHER_INPUT="$root/test/compiler/stage6_declaration_ref_uniqueness_b.s" \
  "$root/bin/s_compiler" declaration-ref-proof "$root/test/compiler/stage6_declaration_ref_uniqueness_a.s" "$report"

grep -qx 'S6.1=PASS' "$report"
grep -qx 'S6.2=PASS' "$report"
grep -qx 'S6.3=PASS' "$report"
grep -qx 'S6.4=PASS' "$report"
grep -qx 'S6.5=PASS' "$report"
grep -qx 'S6.6=PASS' "$report"
grep -qx 'S6.7=PASS' "$report"
grep -qx 'S6.8=PASS' "$report"
grep -qx 'S6.8.canonical-declaration-ref-produced=yes' "$report"
grep -qx 'S6.8.declaration-ref-output-observable=yes' "$report"
grep -qx 'S6.8.output-kind=canonical-declaration-ref' "$report"
grep -qx 'S6.8.output-consumable-by-next-stage=yes' "$report"
grep -qx 'S6.8.not-candidate-output=yes' "$report"
grep -qx 'S6.8.not-display-string-output=yes' "$report"
grep -qx 'S6.8.type-checking-performed=no' "$report"
grep -qx 'S6.8.canonical-type-ref-created=no' "$report"
grep -qx 'S6.8.mir-created=no' "$report"
grep -qx 'S6.8.lowering-performed=no' "$report"
grep -qx 'S6.8.evidence=canonical Stage 6 emits DeclarationRef output at the declaration identity boundary' "$report"

if grep -Eq 'S7\.|Type Checking=PASS|CanonicalTypeRef=PASS|MIR=PASS|type-check-result=|canonical-type-ref=|mir-body=' "$report"; then
  echo "S6.8 proof leaked Stage 7 or later-stage output" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage6 output boundary proof self-test passed"
