#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage6-equality-semantics.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage6-equality-semantics.txt"
S_STAGE6_UNIQUENESS_OTHER_INPUT="$root/test/compiler/stage6_declaration_ref_uniqueness_b.s" \
  "$root/bin/s_compiler" declaration-ref-proof "$root/test/compiler/stage6_declaration_ref_uniqueness_a.s" "$report"

grep -qx 'S6.1=PASS' "$report"
grep -qx 'S6.2=PASS' "$report"
grep -qx 'S6.3=PASS' "$report"
grep -qx 'S6.4=PASS' "$report"
grep -qx 'S6.5=PASS' "$report"
grep -qx 'S6.6=PASS' "$report"
grep -qx 'S6.6.equal-canonical-identities-equal=yes' "$report"
grep -qx 'S6.6.distinct-canonical-identities-unequal=yes' "$report"
grep -qx 'S6.6.same-spelling-different-package-unequal=yes' "$report"
grep -qx 'S6.6.not-display-name-equality=yes' "$report"
grep -qx 'S6.6.not-address-equality=yes' "$report"
grep -qx 'S6.6.evidence=canonical Stage 6 DeclarationRef equality is based on canonical declaration identity' "$report"

if grep -Eq 'S7\.|Type Checking=PASS|CanonicalTypeRef=PASS|MIR=PASS|type-check-result=|canonical-type-ref=|mir-body=' "$report"; then
  echo "S6.6 proof leaked Stage 7 or later-stage output" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage6 equality semantics proof self-test passed"
