#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage8-input-boundary.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage8-input-boundary.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s" \
  "$root/bin/s_compiler" canonical-type-ref-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S8.1=PASS' "$report"
grep -qx 'S8.1.input-stage=stage7' "$report"
grep -qx 'S8.1.input-kind=stage7-type-facts' "$report"
grep -qx 'S8.1.declaration-type-facts-consumed=yes' "$report"
grep -qx 'S8.1.expression-type-facts-consumed=yes' "$report"
grep -qx 'S8.1.declaration-facts-key=canonical-declaration-ref' "$report"
grep -qx 'S8.1.rerun-type-checking=no' "$report"
grep -qx 'S8.1.rerun-name-resolution=no' "$report"
grep -qx 'S8.1.evidence=canonical Stage 8 input boundary consumes Stage 7 DeclarationRef-keyed type facts without claiming canonical type identity' "$report"

if grep -Eq 'S8\.[5-8]=PASS|Semantic Analysis=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S9\.' "$report"; then
  echo "S8.1 proof leaked S8.5+ or later-stage success claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage8 input boundary proof self-test passed"
