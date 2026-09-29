#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/stage7-no-reresolution.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

make -C "$root" compiler >/dev/null

report="$work/stage7-no-reresolution.txt"
S_STAGE7_NEGATIVE_PROOF_INPUT="$root/test/compiler/stage7_type_checking_type_error.s"   "$root/bin/s_compiler" type-checking-proof "$root/test/compiler/stage7_type_checking_basic.s" "$report"

grep -qx 'S7.1=PASS' "$report"
grep -qx 'S7.2=PASS' "$report"
grep -qx 'S7.3=PASS' "$report"
grep -qx 'S7.4=PASS' "$report"
grep -qx 'S7.5=PASS' "$report"
grep -qx 'S7.6=PASS' "$report"
grep -qx 'S7.7=PASS' "$report"
grep -qx 'S7.7.declaration-ref-consumed-directly=yes' "$report"
grep -qx 'S7.7.lookup-from-text=no' "$report"
grep -qx 'S7.7.declaration-ref-reconstructed=no' "$report"
grep -qx 'S7.7.name-reresolution=no' "$report"
grep -qx 'S7.7.evidence=canonical Stage 7 type checking consumes DeclarationRef without re-resolution or identity reconstruction' "$report"

# Provenance must be real: the DeclarationRef Stage 7 consumed must equal the
# Stage 6 stored ref recorded by the real return type-check path.
consumed=$(sed -n 's/^S7.7.declaration-ref=//p' "$report" | tail -n 1)
stored=$(sed -n 's/^S7.7.stage6-stored-ref=//p' "$report" | tail -n 1)
if [ -z "$consumed" ] || [ "$consumed" != "$stored" ]; then
  echo "S7.7 consumed DeclarationRef did not match Stage 6 stored ref" >&2
  cat "$report" >&2
  exit 1
fi

# Reject fabricated counter self-certification and later-stage claims.
if grep -Eq 'stage5-resolution-count|stage6-identity-construction-count' "$report"; then
  echo "S7.7 proof leaked fabricated counter instrumentation" >&2
  cat "$report" >&2
  exit 1
fi
if grep -Eq 'CanonicalTypeRef=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S8\.' "$report"; then
  echo "S7.7 proof leaked later contract or later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage7 no re-resolution proof self-test passed"
