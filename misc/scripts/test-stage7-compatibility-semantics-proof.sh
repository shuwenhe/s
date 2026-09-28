#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-compatibility-semantics.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-compatibility-semantics.txt"
"$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S7.1=PASS' "$report"
grep -qx 'S7.2=PASS' "$report"
grep -qx 'S7.3=PASS' "$report"
grep -qx 'S7.4=PASS' "$report"
grep -qx 'S7.5=PASS' "$report"
grep -qx 'S7.5.compatibility-actual-source=expression-type-fact' "$report"
grep -qx 'S7.5.compatibility-expected-source=declaration-type-fact' "$report"
grep -qx 'S7.5.compatibility-expected-key=canonical-declaration-ref' "$report"
grep -qx 'S7.5.compatibility-result=compatible' "$report"
grep -qx 'S7.5.compatibility-action=accept' "$report"
grep -qx 'S7.5.name-reresolution=no' "$report"
grep -qx 'S7.5.evidence=canonical Stage 7 compatibility consumes expression and declaration type facts on the real return edge' "$report"

if grep -Eq 'S7\.[6-8]=PASS|CanonicalTypeRef|MIR|layout|ABI|codegen|S8\.' "$report"; then
  echo "S7.5 proof leaked later contract or later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 compatibility semantics proof self-test passed"