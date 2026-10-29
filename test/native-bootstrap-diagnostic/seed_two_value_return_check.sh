#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-seed-two-value.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/program.s" <<'S'
package main
struct Failure { string message }
calls := 0
func pair() (int,int) { return 40, 2 }
func first() int { calls = calls * 10 + 1; return 40 }
func second() int { calls = calls * 10 + 2; return 2 }
func ordered() (int,int) { return first(), second() }
func failed() (string,Failure) { return "", Failure { message: "bad" } }
func quad() (int,int,int,int) { return 1, 2, 3, 36 }
func triple() (int,string,bool) { return 40, "payload", true }
func good() (string,Failure) { return "ok", Failure { message: "" } }
func main() int {
    left, right := pair()
    seen := false
    seen = true
    if !seen || left != 40 || right != 2 { return 1 }
    a, b := ordered()
    if calls != 12 || a + b != 42 { return 2 }
    text, error := failed()
    if text != "" || error.message != "bad" { return 3 }
    success, empty := good()
    if success != "ok" || empty.message != "" { return 4 }
    number, label, flag := triple()
    if number != 40 || label != "payload" || !flag { return 5 }
    q0, q1, q2, q3 := quad()
    seen = false
    if seen || q0 != 1 || q1 != 2 || q2 != 3 || q3 != 36 { return 6 }
    return 42
}
S
"$root/bin/s_seed" --compile-native-unit "$work/program.ir" "$root/src/result/result.s" "$work/program.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/program.ir" "$work/program"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/program"
status=0; timeout 10 "$work/program" || status=$?
test "$status" -eq 42
for body in 'return 40, true' 'return 40, 2, 3'; do
    printf 'package main\nfunc wrong() (int,string) { %s }\nfunc main() int { return 42 }\n' "$body" > "$work/invalid.s"
    printf keep > "$work/invalid.ir"
    if "$root/bin/s_seed" --compile-native-unit "$work/invalid.ir" "$root/src/result/result.s" "$work/invalid.s" > "$work/error.log" 2>&1; then
        echo "accepted invalid two-value return: $body" >&2; exit 1
    fi
    test "$(cat "$work/invalid.ir")" = keep
 done
cat > "$work/invalid-binding.s" <<'S'
package main
func pair() (int,int) { return 1, 2 }
func main() int { a, b, c := pair(); return 42 }
S
if "$root/bin/s_seed" --compile-native-unit "$work/invalid.ir" "$root/src/result/result.s" "$work/invalid-binding.s" > "$work/error.log" 2>&1; then
    echo 'accepted three bindings from a two-value producer' >&2; exit 1
fi
cat > "$work/invalid-binding.s" <<'S'
package main
func nested() result[int,result[int,int]] { return result.ok(1) }
func main() int { a, b, c := nested(); return 42 }
S
if "$root/bin/s_seed" --compile-native-unit "$work/invalid.ir" "$root/src/result/result.s" "$work/invalid-binding.s" > "$work/error.log" 2>&1; then
    echo 'flattened a result enum as a three-value source tuple' >&2; exit 1
fi
echo 'Seed native multiple-value returns: both payloads, evaluation once/order, declaration priority and strict arity/types: PASS'
