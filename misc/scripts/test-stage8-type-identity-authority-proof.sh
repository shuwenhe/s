#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage8-type-identity-authority.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage8-type-identity-authority.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s" \
  "$root/bin/s_compiler" canonical-type-ref-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S8.1=PASS' "$report"
grep -qx 'S8.2=PASS' "$report"
grep -qx 'S8.3=PASS' "$report"
grep -qx 'S8.3.identity-authority=canonical-stage8-type-identity' "$report"
grep -qx 'S8.3.identity-source=stage7-type-fact' "$report"
grep -Eq '^S8\.3\.canonical-type-ref=canonical-type-identity:stage7-type-fact:.+' "$report"
grep -qx 'S8.3.independent-of-display-text=yes' "$report"
grep -qx 'S8.3.layout-required=no' "$report"
grep -qx 'S8.3.abi-required=no' "$report"
grep -qx 'S8.3.evidence=canonical Stage 8 TypeRef identity is assigned by canonical-stage8-type-identity authority' "$report"

if grep -Eq 'S8\.[5-8]=PASS|Semantic Analysis=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S9\.' "$report"; then
  echo "S8.3 proof leaked S8.5+ or later-stage success claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage8 type identity authority proof self-test passed"
