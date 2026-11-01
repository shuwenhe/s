#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-ref-return-type-fact.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-ref-return-type-fact.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s" \
  "$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_fact_ref_return_box.s" "$report"

grep -qx 'S7.1=PASS' "$report"
grep -qx 'S7.2=PASS' "$report"
grep -qx 'S7.3=PASS' "$report"
grep -qx 'S7.3.return-type-fact=ref' "$report"
grep -qx 'S7.3.parameter-count-fact=1' "$report"
grep -qx 'S7.4=PASS' "$report"
grep -qx 'S7.4.expression-type-kind=ref' "$report"
grep -Eq '^S7\.8=(PASS|FAIL)$' "$report"

if grep -Eq 'CanonicalTypeRef=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S8\.' "$report"; then
  echo "Stage 7 ref-return proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 ref return observation proof self-test passed"
