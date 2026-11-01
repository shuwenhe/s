#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
script="$root/scripts/canonical-declaration-ref-check.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/canonical-declaration-ref-check.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin" "$tmp/.bootstrap/stage6"

cat >"$tmp/bin/s_compiler" <<'SH'
#!/bin/sh
set -eu
case "${1:-help}" in
  help|--help)
    echo "usage: s_compiler check <input.s>"
    exit 0
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$tmp/bin/s_compiler"

report="$tmp/.bootstrap/stage6/declaration-ref-gate.txt"
status=0
S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/no-proof.out" 2>&1 || status=$?
test "$status" -eq 1
test -f "$report"
grep -qx 'result=FAIL' "$report"
grep -qx 'first-unmet-contract=S6.1' "$report"
grep -qx 'stage6-declaration-ref=NOT_CLOSED' "$report"
grep -q 'reason=.*observable Stage 6 proof' "$report"
if grep -Eq 'PENDING|PENDING_IMPLEMENTATION|PLACEHOLDER|TODO' "$report" "$tmp/no-proof.out"; then
  echo "Stage 6 gate must not report placeholder status" >&2
  cat "$report" >&2
  exit 1
fi

cat >"$tmp/mock-red.txt" <<'EOF'
S6.1=PASS
S6.1.evidence=resolved declaration candidate input observed
S6.2=PASS
S6.2.evidence=canonical producer observed
S6.3=PASS
S6.3.evidence=identity authority observed
S6.4=FAIL
S6.4.reason=stable identity proof not produced
EOF

status=0
S_STAGE6_ALLOW_MOCK_PROOF=1 S_STAGE6_PROOF_REPORT="$tmp/mock-red.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-red.out" 2>&1 || status=$?
test "$status" -eq 4
grep -qx 'result=FAIL' "$report"
grep -qx 'first-unmet-contract=S6.4' "$report"
grep -qx 'S6.1 Input Boundary=PASS' "$report"
grep -qx 'S6.2 Canonical Producer=PASS' "$report"
grep -qx 'S6.3 Identity Authority=PASS' "$report"
grep -qx 'S6.4 Stable Identity=FAIL' "$report"

cat >"$tmp/mock-green.txt" <<'EOF'
S6.1=PASS
S6.1.evidence=input boundary observed
S6.2=PASS
S6.2.evidence=canonical producer observed
S6.3=PASS
S6.3.evidence=identity authority observed
S6.4=PASS
S6.4.evidence=stable identity observed
S6.5=PASS
S6.5.evidence=uniqueness observed
S6.6=PASS
S6.6.evidence=equality semantics observed
S6.7=PASS
S6.7.evidence=no re-resolution observed
S6.8=PASS
S6.8.evidence=output boundary observed
EOF

S_STAGE6_ALLOW_MOCK_PROOF=1 S_STAGE6_PROOF_REPORT="$tmp/mock-green.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-green.out" 2>&1
grep -qx 'result=PASS' "$report"
grep -qx 'first-unmet-contract=NONE' "$report"
grep -qx 'stage6-declaration-ref=CLOSED' "$report"

cat >"$tmp/mock-forbidden.txt" <<'EOF'
S6.1=PASS
S6.1.evidence=Type Checking success is not Stage 6 proof
EOF

status=0
S_STAGE6_ALLOW_MOCK_PROOF=1 S_STAGE6_PROOF_REPORT="$tmp/mock-forbidden.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-forbidden.out" 2>&1 || status=$?
test "$status" -eq 1
grep -qx 'first-unmet-contract=S6.1' "$report"
grep -q 'forbidden later-stage claim' "$report"

echo "canonical declaration ref gate self-test passed"
