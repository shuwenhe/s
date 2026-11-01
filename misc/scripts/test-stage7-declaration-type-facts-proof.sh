#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-declaration-type-facts.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-declaration-type-facts.txt"
"$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S7.1=PASS' "$report"
grep -qx 'S7.2=PASS' "$report"
grep -qx 'S7.3=PASS' "$report"
grep -qx 'S7.3.declaration-type-facts-key=canonical-declaration-ref' "$report"
grep -Eq '^S7\.3\.declaration-ref=canonical-declaration-identity:function:stage7_type_checking_basic:helper$' "$report"
grep -qx 'S7.3.return-type-fact=int' "$report"
grep -qx 'S7.3.parameter-count-fact=0' "$report"
grep -qx 'S7.3.declaration-type-facts-produced=yes' "$report"
grep -qx 'S7.3.declaration-type-facts-consumed=yes' "$report"
grep -qx 'S7.3.name-reresolution=no' "$report"
grep -qx 'S7.3.evidence=canonical Stage 7 declaration type facts for zero-arg callee helper are keyed by DeclarationRef and consumed by the real type checker' "$report"

if grep -Eq 'S7\.[6-8]=PASS|CanonicalTypeRef|MIR|layout|ABI|codegen|S8\.' "$report"; then
  echo "S7.3 proof leaked later contract or later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 declaration type facts proof self-test passed"