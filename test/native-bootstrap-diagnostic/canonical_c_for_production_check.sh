#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-canonical-c-for-native.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "artifacts=$work"; fi' EXIT
cat > "$work/main.s" <<'S'
package main
func main(int input) int {
    total := 1
    for i := 0; i < input; i++ { total += i }
    for ; total < 7; total++ {}
    return total
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
for pair in '0 7' '4 7' '6 16'; do
    read -r input wanted <<< "$pair"
    status=0; "$work/main" "$input" || status=$?
    test "$status" -eq "$wanted"
done
cat > "$work/early.s" <<'S'
package main
func main(int divisor) int { for i := 0; i < 4; i = 10 / divisor { return 42 }; return 7 }
S
"$compiler" --compile-unit "$work/early.sasm" "$work/early.s"
"$compiler" --emit-bin "$work/early.sasm" "$work/early"
status=0; "$work/early" 0 || status=$?
test "$status" -eq 42
printf keep > "$work/rejected.sasm"
for mode in condition scope post; do
    case "$mode" in
        condition) text='func main() int { for i := 0; 3; i++ {}; return 0 }' ;;
        scope) text='func main() int { for i := 0; i < 3; i++ {}; return i }' ;;
        post) text='func main() int { for i := 0; i < 3; missing++ {}; return 0 }' ;;
    esac
    printf 'package main\n%s\n' "$text" > "$work/$mode.s"
    if "$compiler" --compile-unit "$work/rejected.sasm" "$work/$mode.s" > "$work/$mode.log" 2>&1; then
        echo "accepted invalid for $mode" >&2; exit 1
    fi
    test "$(cat "$work/rejected.sasm")" = keep
done
echo 'canonical C-style for native init/condition/post, early return, scope and rejection: PASS'
