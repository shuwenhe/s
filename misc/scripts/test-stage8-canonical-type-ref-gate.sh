#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
report="$root/.bootstrap/stage8/canonical-type-ref-gate.txt"
rm -f "$report"

set +e
make -C "$root" canonical-type-ref-check >/tmp/stage8-canonical-type-ref-gate.out 2>&1
status=$?
set -e

if [ "$status" -ne 2 ]; then
  echo "expected make canonical-type-ref-check to exit 2 for S8.5 RED, got $status" >&2
  cat /tmp/stage8-canonical-type-ref-gate.out >&2
  exit 1
fi

test -f "$report"
grep -qx 'S8.1 Input Boundary=PASS' "$report"
grep -qx 'S8.1.evidence=canonical Stage 8 input boundary consumes Stage 7 DeclarationRef-keyed type facts without claiming canonical type identity' "$report"
grep -qx 'S8.2 Canonical Type Identity Producer=PASS' "$report"
grep -qx 'S8.2.evidence=canonical Stage 8 type identity creation flows through canonical-type-ref-producer' "$report"
grep -qx 'S8.3 Type Identity Authority=PASS' "$report"
grep -qx 'S8.3.evidence=canonical Stage 8 TypeRef identity is assigned by canonical-stage8-type-identity authority' "$report"
grep -qx 'S8.4 Stable Identity=PASS' "$report"
grep -qx 'S8.4.evidence=canonical Stage 8 repeated production from the same Stage 7 type fact yields the same TypeRef identity' "$report"
grep -qx 'S8.5 Uniqueness / Interning Semantics=FAIL' "$report"
grep -qx 'S8.5.reason=no observable proof for S8.5 Uniqueness / Interning Semantics' "$report"
grep -qx 'first-unmet-contract=S8.5' "$report"
grep -qx 'stage8-canonical-type-ref=NOT_CLOSED' "$report"
grep -qx 'result=FAIL' "$report"

if grep -Eq 'S8\.[6-8].*=PASS|Semantic Analysis=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S9\.' "$report"; then
  echo "Stage 8 gate leaked later contract or later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage8 canonical type ref gate S8.5 RED self-test passed"
