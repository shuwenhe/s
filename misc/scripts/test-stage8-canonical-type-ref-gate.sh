#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
report="$root/.bootstrap/stage8/canonical-type-ref-gate.txt"
rm -f "$report"

set +e
make -C "$root" canonical-type-ref-check >/tmp/stage8-canonical-type-ref-gate.out 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "expected make canonical-type-ref-check to exit 0 for Stage 8 CLOSED, got $status" >&2
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
grep -qx 'S8.5 Uniqueness / Interning Semantics=PASS' "$report"
grep -qx 'S8.5.evidence=canonical Stage 8 equal type facts converge and distinct supported type facts produce distinct TypeRef identities' "$report"
grep -qx 'S8.6 Equality Semantics=PASS' "$report"
grep -qx 'S8.6.evidence=canonical Stage 8 equal canonical identities compare equal and distinct identities compare unequal through canonical equality operation' "$report"
grep -qx 'S8.7 No Re-Typechecking Or Identity Reconstruction=PASS' "$report"
grep -qx 'S8.7.evidence=canonical Stage 8 production consumes Stage 7 type facts without re-typechecking or rebuilding declaration identity' "$report"
grep -qx 'S8.8 Output Boundary=PASS' "$report"
grep -qx 'S8.8.evidence=canonical Stage 8 emits CanonicalTypeRef facts through a real output carrier consumable by the next stage boundary' "$report"
grep -qx 'first-unmet-contract=NONE' "$report"
grep -qx 'stage8-canonical-type-ref=CLOSED' "$report"
grep -qx 'result=PASS' "$report"

if grep -Eq 'Semantic Analysis=PASS|MIR=PASS|layout=PASS|ABI=PASS|codegen=PASS|S9\.' "$report"; then
  echo "Stage 8 gate leaked later contract or later-stage claims" >&2
  cat "$report" >&2
  exit 1
fi

echo "stage8 canonical type ref gate CLOSED self-test passed"
