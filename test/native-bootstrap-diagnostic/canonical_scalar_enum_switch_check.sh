#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-scalar-enum-switch.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
enum Kind { one = -3, two = 300 }
func select(Kind kind) int { return switch kind { Kind.one: 42, Kind.two: 43 } }
func main(int input) int { if input == 0 { return select(Kind.one) }; return select(Kind.two) }
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
for pair in '0 42' '1 43'; do
    read -r input expected <<< "$pair"
    status=0; "$work/main" "$input" || status=$?
    test "$status" -eq "$expected"
done
sed 's/enum Kind/enum Other { one }\nenum Kind/; s/Kind.one: 42/Other.one: 42/' "$work/main.s" > "$work/invalid.s"
printf preserve > "$work/rejected.sasm"
if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/invalid.log" 2>&1; then
    echo 'pattern from different enum accepted' >&2; exit 1
fi
grep -q 'canonical semantic:' "$work/invalid.log"
test "$(cat "$work/rejected.sasm")" = preserve
echo 'scalar enum switch patterns retain nominal identity and explicit discriminants: PASS'
