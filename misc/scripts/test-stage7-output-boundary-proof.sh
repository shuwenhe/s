#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-output-boundary.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-output-boundary.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s"   "$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S7.1=PASS' "$report"
grep -qx 'S7.2=PASS' "$report"
grep -qx 'S7.3=PASS' "$report"
grep -qx 'S7.4=PASS' "$report"
grep -qx 'S7.5=PASS' "$report"
grep -qx 'S7.6=PASS' "$report"
grep -qx 'S7.7=PASS' "$report"
grep -qx 'S7.8=PASS' "$report"
grep -qx 'S7.8.output-kind=stage7-type-facts' "$report"
grep -qx 'S7.8.declaration-type-facts-output=yes' "$report"
grep -qx 'S7.8.expression-type-facts-output=yes' "$report"
grep -qx 'S7.8.declaration-facts-key=canonical-declaration-ref' "$report"
grep -qx 'S7.8.expression-facts-key=canonical-declaration-ref' "$report"
grep -qx 'S7.8.consumable-by-stage8=yes' "$report"
grep -qx 'S7.8.stage8-rerun-type-checking-required=no' "$report"
grep -qx 'S7.8.stage8-rerun-name-resolution-required=no' "$report"
grep -qx 'S7.8.canonical-type-ref-created=no' "$report"
grep -qx 'S7.8.mir-created=no' "$report"
grep -qx 'S7.8.layout-computed=no' "$report"
grep -qx 'S7.8.abi-classified=no' "$report"
grep -qx 'S7.8.codegen-performed=no' "$report"
grep -qx 'S7.8.evidence=canonical Stage 7 emits DeclarationRef-keyed type facts consumable by the next stage without claiming later-stage authority' "$report"

if grep -Eq 'CanonicalTypeRef=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S8\.' "$report"; then
  echo "S7.8 proof leaked later-stage success claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 output boundary proof self-test passed"
