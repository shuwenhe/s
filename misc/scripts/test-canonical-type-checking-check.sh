#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
script="$root/scripts/canonical-type-checking-check.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/canonical-type-checking-check.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin" "$tmp/.bootstrap/stage7"

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

report="$tmp/.bootstrap/stage7/type-checking-gate.txt"
status=0
S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/no-proof.out" 2>&1 || status=$?
test "$status" -eq 1
test -f "$report"
grep -qx 'result=FAIL' "$report"
grep -qx 'first-unmet-contract=S7.1' "$report"
grep -qx 'stage7-type-checking=NOT_CLOSED' "$report"
grep -q 'reason=.*observable Stage 7 proof' "$report"
if grep -Eq 'PENDING|PENDING_IMPLEMENTATION|PLACEHOLDER|TODO' "$report" "$tmp/no-proof.out"; then
  echo "Stage 7 gate must not report placeholder status" >&2
  cat "$report" >&2
  exit 1
fi

cat >"$tmp/mock-red.txt" <<'EOF_RED'
S7.1=PASS
S7.1.evidence=input boundary observed
S7.2=PASS
S7.2.evidence=type environment authority observed
S7.3=PASS
S7.3.evidence=declaration type facts observed
S7.4=FAIL
S7.4.reason=expression type facts proof not produced
EOF_RED

status=0
S_STAGE7_ALLOW_MOCK_PROOF=1 S_STAGE7_PROOF_REPORT="$tmp/mock-red.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-red.out" 2>&1 || status=$?
test "$status" -eq 4
grep -qx 'result=FAIL' "$report"
grep -qx 'first-unmet-contract=S7.4' "$report"
grep -qx 'S7.1 Input Boundary=PASS' "$report"
grep -qx 'S7.2 Type Environment Authority=PASS' "$report"
grep -qx 'S7.3 Declaration Type Facts=PASS' "$report"
grep -qx 'S7.4 Expression Type Facts=FAIL' "$report"

cat >"$tmp/mock-green.txt" <<'EOF_GREEN'
S7.1=PASS
S7.1.evidence=input boundary observed
S7.2=PASS
S7.2.evidence=type environment authority observed
S7.3=PASS
S7.3.evidence=declaration type facts observed
S7.4=PASS
S7.4.evidence=expression type facts observed
S7.5=PASS
S7.5.evidence=compatibility semantics observed
S7.6=PASS
S7.6.evidence=type error rejection observed
S7.7=PASS
S7.7.evidence=no re-resolution or identity reconstruction observed
S7.8=PASS
S7.8.evidence=output boundary observed
EOF_GREEN

S_STAGE7_ALLOW_MOCK_PROOF=1 S_STAGE7_PROOF_REPORT="$tmp/mock-green.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-green.out" 2>&1
grep -qx 'result=PASS' "$report"
grep -qx 'first-unmet-contract=NONE' "$report"
grep -qx 'stage7-type-checking=CLOSED' "$report"

cat >"$tmp/mock-forbidden.txt" <<'EOF_FORBIDDEN'
S7.1=PASS
S7.1.evidence=CanonicalTypeRef success is not Stage 7 proof
EOF_FORBIDDEN

status=0
S_STAGE7_ALLOW_MOCK_PROOF=1 S_STAGE7_PROOF_REPORT="$tmp/mock-forbidden.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-forbidden.out" 2>&1 || status=$?
test "$status" -eq 1
grep -qx 'first-unmet-contract=S7.1' "$report"
grep -q 'forbidden later-stage claim' "$report"

echo "canonical type checking gate self-test passed"
