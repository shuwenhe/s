#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-reachability.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
seed := 41
answer := seed + 1
func unused() string { return "UNREACHABLE_COMPILER_FORWARDER S_BOOTSTRAP_BASE_COMPILER" }
func first(int input) int { if input == 0 { return answer }; return second(input - 1) }
func second(int input) int { if input == 0 { return answer }; return first(input - 1) }
func main(int input) int { return first(input) }
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
for input in 0 5; do
    status=0; "$work/main" "$input" || status=$?
    test "$status" -eq 42
done
if strings "$work/main" | grep -q UNREACHABLE_COMPILER_FORWARDER; then
    echo 'unreachable function payload retained in executable' >&2; exit 1
fi
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
cat > "$work/invalid.s" <<'S'
package main
func unused() int { return missing_name }
func main() int { return 42 }
S
printf preserve > "$work/preserved.sasm"
if "$compiler" --compile-unit "$work/preserved.sasm" "$work/invalid.s" > "$work/error.log" 2>&1; then
    echo 'unreachable invalid function skipped semantic checking' >&2; exit 1
fi
grep -q 'canonical semantic:' "$work/error.log"
test "$(cat "$work/preserved.sasm")" = preserve
echo 'native reachability keeps recursion/global initializers, removes dead payloads, and checks all source: PASS'
