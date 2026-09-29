#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-ref-return-type-fact.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-ref-return-type-fact.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s" \
  "$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_fact_ref_return_box.s" "$report"

grep -qx 'S7.3.return-type-fact=ref(box)' "$report"
grep -qx 'S7.4.expression-type-kind=ref(box)' "$report"
grep -qx 'S7.8.type-fact-component-preserved=yes' "$report"
grep -qx 'S7.8.type-fact-nesting-preserved=yes' "$report"
grep -qx 'S7.8.reference-type-fact=ref(box)' "$report"

if grep -Eq '^S7\.[34].*=.*=ref$|return-type-fact=ref$|expression-type-kind=ref$|CanonicalTypeRef=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S8\.' "$report"; then
  echo "Stage 7 ref type fact collapsed or leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 ref return type fact proof self-test passed"
