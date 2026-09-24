#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
script="$root/misc/scripts/canonical-resolution-closure-check.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/canonical-resolution-closure-test.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/src"

cat >"$tmp/compiler_no_resolve" <<'SH'
#!/bin/sh
set -eu
cmd=${1:-help}
case "$cmd" in
  help|--help)
    cat >&2 <<'EOF'
usage: s_modular check <input.s>
       s_modular tokens <input.s>
       s_modular ast <input.s>
       s_modular build <input.s> -o <output>
EOF
    exit 2
    ;;
  tokens|ast)
    exit 0
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$tmp/compiler_no_resolve"

cat >"$tmp/compiler_with_resolve" <<'SH'
#!/bin/sh
set -eu
cmd=${1:-help}
file=${2:-}
case "$cmd" in
  help|--help)
    cat >&2 <<'EOF'
usage: s_modular resolve <input.s>
EOF
    exit 2
    ;;
  tokens|ast)
    exit 0
    ;;
  resolve)
    if grep -q 'UNRESOLVED_NAME' "$file"; then
      echo "$file:1:1: resolution error: unresolved name missing_symbol" >&2
      exit 1
    fi
    if grep -q 'DECLARATION_IDENTITY_ERROR' "$file"; then
      echo "$file:1:1: declaration-ref error: missing declaration identity" >&2
      exit 1
    fi
    echo "resolution-ok=PASS"
    echo "declaration-ref-ok=PASS"
    exit 0
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$tmp/compiler_with_resolve"

cat >"$tmp/src/ok.s" <<'EOF'
package ok
func main() {}
EOF
cat >"$tmp/src/bad.s" <<'EOF'
package bad
UNRESOLVED_NAME
EOF

printf '%s
' "$tmp/src/ok.s" >"$tmp/no-resolve.closure"
no_resolve_report="$tmp/no-resolve.report"
no_resolve_status=0
S_SOURCE_ROOT="$tmp" "$script" "$tmp/compiler_no_resolve" "$tmp/no-resolve.closure" "$no_resolve_report" >/dev/null 2>&1 || no_resolve_status=$?
test "$no_resolve_status" -ne 0
grep -qx 'resolution-stop-point=NOT_FOUND' "$no_resolve_report"
grep -qx 'stage5-resolution=NOT_OBSERVABLE' "$no_resolve_report"
grep -qx 'stage6-declaration-ref=NOT_OBSERVABLE' "$no_resolve_report"
grep -qx 'result=FAIL' "$no_resolve_report"

printf '%s
' "$tmp/src/ok.s" "$tmp/src/bad.s" >"$tmp/red.closure"
red_report="$tmp/red.report"
red_status=0
S_SOURCE_ROOT="$tmp" "$script" "$tmp/compiler_with_resolve" "$tmp/red.closure" "$red_report" >/dev/null 2>&1 || red_status=$?
test "$red_status" -ne 0
grep -qx 'resolution-stop-point=FOUND' "$red_report"
grep -qx 'closure-files=2' "$red_report"
grep -qx 'ast-ok=2' "$red_report"
grep -qx 'resolution-ok=1' "$red_report"
grep -qx 'unresolved-names=1' "$red_report"
grep -qx 'first-failure-stage=5' "$red_report"
grep -qx 'stage5-resolution=NOT_CLOSED' "$red_report"
grep -qx 'stage6-declaration-ref=NOT_CLOSED' "$red_report"
grep -qx 'result=FAIL' "$red_report"

printf '%s
' "$tmp/src/ok.s" >"$tmp/green.closure"
green_report="$tmp/green.report"
S_SOURCE_ROOT="$tmp" "$script" "$tmp/compiler_with_resolve" "$tmp/green.closure" "$green_report" >/dev/null
grep -qx 'resolution-stop-point=FOUND' "$green_report"
grep -qx 'closure-files=1' "$green_report"
grep -qx 'resolution-ok=1' "$green_report"
grep -qx 'declaration-ref-ok=1' "$green_report"
grep -qx 'stage5-resolution=CLOSED' "$green_report"
grep -qx 'stage6-declaration-ref=CLOSED' "$green_report"
grep -qx 'result=PASS' "$green_report"

echo "canonical resolution closure gate self-test passed"
