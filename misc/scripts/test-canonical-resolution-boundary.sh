#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_modular"}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/canonical-resolution-boundary.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cat >"$tmp/minimal_valid.s" <<'SRC'
package main
func helper() int { return 1 }
func main() int { return helper() }
SRC

cat >"$tmp/unresolved_name.s" <<'SRC'
package main
func main() int { return missing_symbol() }
SRC

cat >"$tmp/type_invalid.s" <<'SRC'
package main
func value() int { return 1 }
func main() int { return value("wrong") }
SRC

help_status=0
"$compiler" help >"$tmp/help.out" 2>&1 || help_status=$?
grep -Eq '(^|[[:space:]])resolve([[:space:]]|$)' "$tmp/help.out"

"$compiler" tokens "$tmp/minimal_valid.s" >/dev/null
"$compiler" ast "$tmp/minimal_valid.s" >/dev/null
"$compiler" resolve "$tmp/minimal_valid.s" >"$tmp/minimal_valid.resolve" 2>&1
grep -qx 'resolve ok: .*minimal_valid\.s' "$tmp/minimal_valid.resolve"
grep -Eq '^declarations=[1-9][0-9]*$' "$tmp/minimal_valid.resolve"
grep -qx 'declaration-ref-ok=PASS' "$tmp/minimal_valid.resolve"

unresolved_status=0
"$compiler" resolve "$tmp/unresolved_name.s" >"$tmp/unresolved_name.resolve" 2>&1 || unresolved_status=$?
test "$unresolved_status" -ne 0
grep -Eq 'stage5-resolution=FAIL|undefined function|unresolved name' "$tmp/unresolved_name.resolve"

"$compiler" resolve "$tmp/type_invalid.s" >"$tmp/type_invalid.resolve" 2>&1
grep -qx 'resolve ok: .*type_invalid\.s' "$tmp/type_invalid.resolve"
check_status=0
"$compiler" check "$tmp/type_invalid.s" >"$tmp/type_invalid.check" 2>&1 || check_status=$?
test "$check_status" -ne 0

echo "canonical resolution boundary self-test passed"
