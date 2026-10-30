#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-external-reachability.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
"$root/bin/s_seed" --compile-native-unit "$work/contracts.ir" \
    "$root/src/cmd/compile/internal/mir/program.s" "$root/src/cmd/compile/internal/mir/program_enum.s" \
    "$root/src/cmd/compile/internal/ssa/program.s" "$root/src/cmd/compile/internal/ssa/function_lower.s" \
    "$root/test/function-ssa/external_test.s"
"$root/bin/s_seed" --emit-standalone-amd64 "$work/contracts.ir" "$work/contracts"
"$work/contracts"
cat > "$work/main.s" <<'S'
package main
struct Error { string message }
extern "intrinsic" func unavailable(string path) (string, Error)
func unused(string path) (string, Error) { return unavailable(path) }
func main() int { return 42 }
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
# A reachable unresolved declaration must fail before replacing the artifact.
sed 's/func main() int { return 42 }/func main() int { text, error := unused("input"); return len(text) }/' "$work/main.s" > "$work/reachable.s"
printf preserve > "$work/rejected.sasm"
if "$compiler" --compile-unit "$work/rejected.sasm" "$work/reachable.s" > "$work/rejected.log" 2>&1; then
    echo 'reachable unresolved external accepted' >&2; exit 1
fi
grep -q 'unresolved external function' "$work/rejected.log"
test "$(cat "$work/rejected.sasm")" = preserve
# Every unused ordinary function must still pass semantic validation.
sed 's/return unavailable(path)/return 1/' "$work/main.s" > "$work/invalid.s"
if "$compiler" --compile-unit "$work/rejected.sasm" "$work/invalid.s" > "$work/invalid.log" 2>&1; then
    echo 'invalid unused function skipped' >&2; exit 1
fi
grep -q 'canonical semantic:' "$work/invalid.log"
test "$(cat "$work/rejected.sasm")" = preserve
echo 'validated unused external declarations prune; reachable unresolved calls reject: PASS'
