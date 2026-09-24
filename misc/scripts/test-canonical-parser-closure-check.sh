#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
script="$root/misc/scripts/canonical-parser-closure-check.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/canonical-parser-closure-test.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/src"

cat >"$tmp/parser" <<'SH'
#!/bin/sh
set -eu
cmd=$1
file=$2
case "$cmd" in
  tokens)
    if grep -q 'LEX_ERROR' "$file"; then
      echo "$file:1:1: lex error: illegal character" >&2
      exit 1
    fi
    exit 0
    ;;
  ast)
    if grep -q 'PARSE_ERROR' "$file"; then
      echo "$file:2:3: parse error: expected expression" >&2
      exit 1
    fi
    if grep -q 'UNSUPPORTED_SYNTAX' "$file"; then
      echo "$file:3:1: unsupported syntax: pattern switch" >&2
      exit 1
    fi
    if grep -q 'SOURCE_DEFECT' "$file"; then
      echo "$file:4:9: parse error: expected ')'" >&2
      exit 1
    fi
    if grep -q 'PARSER_CRASH' "$file"; then
      echo "panic: parser crashed" >&2
      exit 134
    fi
    exit 0
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$tmp/parser"

cat >"$tmp/src/valid1.s" <<'EOF'
package valid1
func main() {}
EOF
cat >"$tmp/src/valid2.s" <<'EOF'
package valid2
func main() {}
EOF
cat >"$tmp/src/parser_invalid.s" <<'EOF'
package bad
PARSE_ERROR
EOF

printf '%s\n' "$tmp/src/valid1.s" "$tmp/src/parser_invalid.s" >"$tmp/red.closure"
red_report="$tmp/red.report"
red_status=0
S_SOURCE_ROOT="$tmp" "$script" "$tmp/parser" "$tmp/red.closure" "$red_report" >/dev/null 2>&1 || red_status=$?
test "$red_status" -ne 0
grep -qx 'closure-files=2' "$red_report"
grep -qx 'lex-ok=2' "$red_report"
grep -qx 'parsed-ok=1' "$red_report"
grep -qx 'parse-errors=1' "$red_report"
grep -qx 'result=FAIL' "$red_report"
grep -q 'class=PARSE_ERROR' "$red_report"

printf '%s\n' "$tmp/src/valid1.s" "$tmp/src/valid2.s" >"$tmp/green.closure"
green_report="$tmp/green.report"
S_SOURCE_ROOT="$tmp" "$script" "$tmp/parser" "$tmp/green.closure" "$green_report" >/dev/null
grep -qx 'closure-files=2' "$green_report"
grep -qx 'lex-ok=2' "$green_report"
grep -qx 'parsed-ok=2' "$green_report"
grep -qx 'parse-errors=0' "$green_report"
grep -qx 'unsupported-syntax=0' "$green_report"
grep -qx 'parser-crashes=0' "$green_report"
grep -qx 'regression-failures=0' "$green_report"
grep -qx 'result=PASS' "$green_report"

echo "canonical parser closure gate self-test passed"
