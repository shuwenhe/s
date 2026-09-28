#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage6-input-boundary.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage6-input-boundary.txt"
"$root/bin/s_compiler" declaration-ref-proof "$root/test/compiler/stage6_declaration_ref_basic.s" "$report"

grep -qx 'S6.1=PASS' "$report"
grep -qx 'S6.1.input-kind=resolved-declaration-candidate' "$report"
grep -qx 'S6.1.candidate-package=stage6_declaration_ref_basic' "$report"
grep -qx 'S6.1.candidate-name=helper' "$report"
grep -qx 'S6.1.candidate-kind=function' "$report"
grep -qx 'S6.1.no-raw-name-input=yes' "$report"
grep -qx 'S6.1.boundary-source=canonical-stage5-resolved-candidate' "$report"
grep -qx 'S6.1.evidence=canonical Stage 6 consumed Stage 5 resolved declaration candidate stage6_declaration_ref_basic.helper' "$report"

if grep -Eq 'Type Checking|CanonicalTypeRef|MIR|layout|ABI|codegen' "$report"; then
  echo "S6.1 proof leaked later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage6 input boundary proof self-test passed"
