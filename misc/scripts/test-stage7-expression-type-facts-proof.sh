#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-expression-type-facts.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-expression-type-facts.txt"
"$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S7.1=PASS' "$report"
grep -qx 'S7.2=PASS' "$report"
grep -qx 'S7.3=PASS' "$report"
grep -qx 'S7.4=PASS' "$report"
grep -qx 'S7.4.expression-kind=call' "$report"
grep -Eq '^S7\.4\.expression-declaration-ref=canonical-declaration-identity:function:stage7_type_checking_basic:helper$' "$report"
grep -qx 'S7.4.expression-type-kind=int' "$report"
grep -qx 'S7.4.expression-type-produced=yes' "$report"
grep -qx 'S7.4.expression-type-consumed=yes' "$report"
grep -qx 'S7.4.expression-type-source=declaration-type-facts' "$report"
grep -qx 'S7.4.name-reresolution=no' "$report"
grep -qx 'S7.4.evidence=canonical Stage 7 call expression facts for zero-arg callee helper are produced and consumed by the real type checker' "$report"

if grep -Eq 'S7\.[6-8]=PASS|CanonicalTypeRef|MIR|layout|ABI|codegen|S8\.' "$report"; then
  echo "S7.4 proof leaked later contract or later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 expression type facts proof self-test passed"


echo "stage7 expression type facts proof self-test passed"