#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage6-canonical-producer.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage6-canonical-producer.txt"
"$root/bin/s_compiler" declaration-ref-proof "$root/test/compiler/stage6_declaration_ref_basic.s" "$report"

grep -qx 'S6.1=PASS' "$report"
grep -qx 'S6.2=PASS' "$report"
grep -qx 'S6.2.producer=canonical-declaration-ref-producer' "$report"
grep -qx 'S6.2.alternate-producers-accepted=no' "$report"
grep -qx 'S6.2.evidence=canonical Stage 6 DeclarationRef identity established by canonical-declaration-ref-producer' "$report"

if grep -Eq 'grep|source-scan|test-only-producer' "$report"; then
  echo "S6.2 proof used forbidden producer evidence" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage6 canonical producer proof self-test passed"
