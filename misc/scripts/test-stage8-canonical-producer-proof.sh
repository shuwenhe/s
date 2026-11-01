#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage8-canonical-producer.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage8-canonical-producer.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s" \
  "$root/bin/s_compiler" canonical-type-ref-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S8.1=PASS' "$report"
grep -qx 'S8.2=PASS' "$report"
grep -qx 'S8.2.producer=canonical-type-ref-producer' "$report"
grep -qx 'S8.2.input-kind=stage7-type-fact' "$report"
grep -qx 'S8.2.input-source=stage7-type-facts' "$report"
grep -qx 'S8.2.canonical-type-ref-created=yes' "$report"
grep -qx 'S8.2.alternate-producers-accepted=no' "$report"
grep -qx 'S8.2.evidence=canonical Stage 8 type identity creation flows through canonical-type-ref-producer' "$report"

if grep -Eq 'S8\.[5-8]=PASS|Semantic Analysis=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S9\.' "$report"; then
  echo "S8.2 proof leaked S8.5+ or later-stage success claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage8 canonical producer proof self-test passed"
