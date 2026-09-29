#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage8-uniqueness-interning.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage8-uniqueness-interning.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s" \
S_STAGE8_UNIQUENESS_OTHER_INPUT="$root/test/compiler/stage8_canonical_type_ref_string.s" \
  "$root/bin/s_compiler" canonical-type-ref-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S8.1=PASS' "$report"
grep -qx 'S8.2=PASS' "$report"
grep -qx 'S8.3=PASS' "$report"
grep -qx 'S8.4=PASS' "$report"
grep -qx 'S8.5=PASS' "$report"
grep -qx 'S8.5.equal-type-facts-converge=yes' "$report"
grep -qx 'S8.5.distinct-supported-type-facts-distinct=yes' "$report"
grep -qx 'S8.5.declaration-type-fact-covered=yes' "$report"
grep -qx 'S8.5.expression-type-fact-covered=yes' "$report"
grep -qx 'S8.5.distinct-pair=int-vs-string' "$report"
grep -qx 'S8.5.evidence=canonical Stage 8 equal type facts converge and distinct supported type facts produce distinct TypeRef identities' "$report"

int_identity=$(sed -n 's/^S8.5.identity-int=//p' "$report")
string_identity=$(sed -n 's/^S8.5.identity-string=//p' "$report")
test -n "$int_identity"
test -n "$string_identity"
test "$int_identity" != "$string_identity"

if grep -Eq 'S8\.[6-8]=PASS|Semantic Analysis=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S9\.' "$report"; then
  echo "S8.5 proof leaked S8.6+ or later-stage success claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage8 uniqueness interning proof self-test passed"
