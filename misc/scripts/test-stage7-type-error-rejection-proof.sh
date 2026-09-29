#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-type-error-rejection.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-type-error-rejection.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s" \
  "$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S7.1=PASS' "$report"
grep -qx 'S7.2=PASS' "$report"
grep -qx 'S7.3=PASS' "$report"
grep -qx 'S7.4=PASS' "$report"
grep -qx 'S7.5=PASS' "$report"
grep -qx 'S7.6=PASS' "$report"
grep -qx 'S7.6.rejection-source=real-type-checker' "$report"
grep -qx 'S7.6.rejection-kind=return-type-mismatch' "$report"
grep -qx 'S7.6.diagnostic=return type mismatch' "$report"
grep -qx 'S7.6.stage5-succeeded-before-rejection=yes' "$report"
grep -qx 'S7.6.stage6-succeeded-before-rejection=yes' "$report"
grep -qx 'S7.6.rejection-attributed-to-stage7=yes' "$report"
grep -qx 'S7.6.expected-key=canonical-declaration-ref' "$report"
grep -qx 'S7.6.name-reresolution=no' "$report"
grep -qx 'S7.6.evidence=canonical Stage 7 rejects an incompatible return after Stage 5 and Stage 6 succeed' "$report"

if grep -Eq 'CanonicalTypeRef=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S8\.' "$report"; then
  echo "S7.6 proof leaked later-stage success claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 type error rejection proof self-test passed"
