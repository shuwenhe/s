#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage8-stable-identity.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage8-stable-identity.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s" \
  "$root/bin/s_compiler" canonical-type-ref-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S8.1=PASS' "$report"
grep -qx 'S8.2=PASS' "$report"
grep -qx 'S8.3=PASS' "$report"
grep -qx 'S8.4=PASS' "$report"
grep -qx 'S8.4.same-type-fact-equal=yes' "$report"
grep -qx 'S8.4.observation-count=2' "$report"
grep -qx 'S8.4.not-address-identity=yes' "$report"
grep -qx 'S8.4.not-call-order-counter=yes' "$report"
grep -qx 'S8.4.evidence=canonical Stage 8 repeated production from the same Stage 7 type fact yields the same TypeRef identity' "$report"

identity_a=$(sed -n 's/^S8.4.identity-a=//p' "$report")
identity_b=$(sed -n 's/^S8.4.identity-b=//p' "$report")
test -n "$identity_a"
test "$identity_a" = "$identity_b"

if grep -Eq 'S8\.[5-8]=PASS|distinct.*identity|Semantic Analysis=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S9\.' "$report"; then
  echo "S8.4 proof leaked S8.5+ or later-stage success claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage8 stable identity proof self-test passed"
