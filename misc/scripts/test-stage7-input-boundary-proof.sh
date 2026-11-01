#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-input-boundary.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-input-boundary.txt"
"$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S7.1=PASS' "$report"
grep -qx 'S7.1.input-stage=stage6' "$report"
grep -qx 'S7.1.input-kind=declaration-ref-plus-expressions' "$report"
grep -qx 'S7.1.declaration-ref-consumed=yes' "$report"
grep -qx 'S7.1.no-raw-name-input=yes' "$report"
grep -qx 'S7.1.boundary-source=canonical-stage6-declaration-ref-output' "$report"
grep -Eq '^S7\.1\.declaration-ref-identity=canonical-declaration-identity:function:stage7_type_checking_basic:helper$' "$report"
grep -qx 'S7.1.expression-input-observed=yes' "$report"
grep -qx 'S7.1.evidence=canonical Stage 7 consumed Stage 6 DeclarationRef output with expression input' "$report"

if grep -Eq 'S7\.[6-8]=PASS|CanonicalTypeRef|MIR|layout|ABI|codegen|S8\.' "$report"; then
  echo "S7.1 proof leaked later contract or later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 input boundary proof self-test passed"
