#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
script="$root/scripts/canonical-name-resolution-check.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/canonical-name-resolution-check.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin" "$tmp/.bootstrap/stage5"

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

report="$tmp/.bootstrap/stage5/name-resolution-gate.txt"
status=0
S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/no-proof.out" 2>&1 || status=$?
test "$status" -eq 1
test -f "$report"
grep -qx 'result=FAIL' "$report"
grep -qx 'first-unmet-contract=S5.1' "$report"
grep -qx 'stage5-name-resolution=NOT_CLOSED' "$report"
grep -q 'reason=.*observable Stage 5 proof' "$report"
if grep -Eq 'PENDING|PENDING_IMPLEMENTATION|PLACEHOLDER|TODO' "$report" "$tmp/no-proof.out"; then
  echo "Stage 5 gate must not report placeholder status" >&2
  cat "$report" >&2
  exit 1
fi

cat >"$tmp/mock-proof.txt" <<'EOF'
S5.1=PASS
S5.1.evidence=canonical AST input authority observed
S5.2=PASS
S5.2.evidence=package identity fixture observed
S5.3=PASS
S5.3.evidence=import registration fixture observed
S5.4=FAIL
S5.4.reason=declaration index proof not produced
EOF

status=0
S_STAGE5_ALLOW_MOCK_PROOF=1 S_STAGE5_PROOF_REPORT="$tmp/mock-proof.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-red.out" 2>&1 || status=$?
test "$status" -eq 4
grep -qx 'result=FAIL' "$report"
grep -qx 'first-unmet-contract=S5.4' "$report"
grep -qx 'S5.1 Input Authority=PASS' "$report"
grep -qx 'S5.2 Package Identity=PASS' "$report"
grep -qx 'S5.3 Import Registration=PASS' "$report"
grep -qx 'S5.4 Declaration Index=FAIL' "$report"

cat >"$tmp/mock-green.txt" <<'EOF'
S5.1=PASS
S5.1.evidence=canonical AST input authority observed
S5.2=PASS
S5.2.evidence=package identity fixture observed
S5.3=PASS
S5.3.evidence=import registration fixture observed
S5.4=PASS
S5.4.evidence=declaration index fixture observed
S5.5=PASS
S5.5.evidence=unqualified lookup fixture observed
S5.6=PASS
S5.6.evidence=qualified lookup fixture observed
S5.7=PASS
S5.7.evidence=ambiguity rejection fixture observed
S5.8=PASS
S5.8.evidence=unresolved rejection fixture observed
S5.9=PASS
S5.9.evidence=resolved declaration candidate boundary observed
EOF

S_STAGE5_ALLOW_MOCK_PROOF=1 S_STAGE5_PROOF_REPORT="$tmp/mock-green.txt" \
  S_SOURCE_ROOT="$tmp" "$script" "$tmp" >"$tmp/mock-green.out" 2>&1
grep -qx 'result=PASS' "$report"
grep -qx 'first-unmet-contract=NONE' "$report"
grep -qx 'stage5-name-resolution=CLOSED' "$report"

echo "canonical name resolution gate self-test passed"
