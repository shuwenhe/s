#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage6-no-reresolution.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage6-no-reresolution.txt"
S_STAGE6_UNIQUENESS_OTHER_INPUT="$root/test/compiler/stage6_declaration_ref_uniqueness_b.s" \
  "$root/bin/s_compiler" declaration-ref-proof "$root/test/compiler/stage6_declaration_ref_uniqueness_a.s" "$report"

grep -qx 'S6.1=PASS' "$report"
grep -qx 'S6.2=PASS' "$report"
grep -qx 'S6.3=PASS' "$report"
grep -qx 'S6.4=PASS' "$report"
grep -qx 'S6.5=PASS' "$report"
grep -qx 'S6.6=PASS' "$report"
grep -qx 'S6.7=PASS' "$report"
grep -qx 'S6.7.from-resolved-candidate=yes' "$report"
grep -qx 'S6.7.lookup-from-text=no' "$report"
grep -qx 'S6.7.accepts-unresolved-name=no' "$report"
grep -qx 'S6.7.additional-name-resolution=0' "$report"
grep -qx 'S6.7.candidate-consumed-directly=yes' "$report"
grep -Eq '^S6\.7\.stage5-resolution-count-before-stage6=[0-9][0-9]*$' "$report"
grep -Eq '^S6\.7\.stage5-resolution-count-after-stage6=[0-9][0-9]*$' "$report"

before=$(sed -n 's/^S6\.7\.stage5-resolution-count-before-stage6=//p' "$report")
after=$(sed -n 's/^S6\.7\.stage5-resolution-count-after-stage6=//p' "$report")
if [ "$before" != "$after" ]; then
  echo "S6.7 proof observed additional Stage 5 resolution during Stage 6" >&2
  cat "$report" >&2
  exit 1
fi

grep -qx 'S6.7.evidence=canonical Stage 6 constructs DeclarationRef from resolved candidate without textual name re-resolution' "$report"

if grep -Eq 'lookup-source=canonical-compiler-find-func|qualified-lookup|unqualified-lookup|S7\.|Type Checking=PASS|CanonicalTypeRef=PASS|MIR=PASS|type-check-result=|canonical-type-ref=|mir-body=' "$report"; then
  echo "S6.7 proof leaked lookup or later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage6 no re-resolution proof self-test passed"
