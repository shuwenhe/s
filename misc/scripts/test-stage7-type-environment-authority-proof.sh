#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-type-environment-authority.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-type-environment-authority.txt"
"$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S7.1=PASS' "$report"
grep -qx 'S7.2=PASS' "$report"
grep -qx 'S7.2.type-env-authority=canonical-declaration-ref' "$report"
grep -Eq '^S7\.2\.declaration-ref=canonical-declaration-identity:function:stage7_type_checking_basic:helper$' "$report"
grep -qx 'S7.2.type-env-lookup=success' "$report"
grep -qx 'S7.2.name-reresolution=no' "$report"
grep -qx 'S7.2.type-checking-producer=canonical-type-checking-producer' "$report"
grep -qx 'S7.2.evidence=canonical Stage 7 type environment established by canonical DeclarationRef authority for zero-arg callee helper' "$report"

if grep -Eq 'S7\.[6-8]=PASS|CanonicalTypeRef|MIR|layout|ABI|codegen|S8\.' "$report"; then
  echo "S7.2 proof leaked later contract or later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 type environment authority proof self-test passed"