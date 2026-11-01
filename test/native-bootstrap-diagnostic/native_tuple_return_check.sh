#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-tuple-return.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "tuple artifacts: $work" >&2; fi' EXIT
cat > "$work/main.s" <<'S'
package main
struct failure { int code }
enum number { value(int) }
func choose(bool ok) (number, failure) {
    if ok { return number.value(42) }
    return failure { code: 7 }
}
func main() int {
    failed := choose(false)
    switch failed {
        std.result.result.ok(_): return 3,
        std.result.result.err(e): { if e.code != 7 { return 4 } }
    }
    match := choose(true)
    switch match {
        std.result.result.ok(n): {
            switch n { number.value(v): return v }
        }
        std.result.result.err(e): return e.code,
    }
}
S
"$root/bin/s_seed" --compile-native-unit "$work/test.ir" "$root/src/result/result.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/test.ir" "$work/test"
status=0; "$work/test" || status=$?; test "$status" -eq 42
cat > "$work/wrong.s" <<'S'
package main
struct holder { std.result.result[int,string] item }
func wrong() (int,string) {
    unused := holder { item: 42 }
    return 42
}
func main() int { return 42 }
S
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/result/result.s" "$work/wrong.s" > "$work/wrong.log" 2>&1; then
    echo 'tuple return conversion escaped into field initialization' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
grep -q 'field type mismatch' "$work/wrong.log"
echo 'native tuple success/error returns preserve enum payloads and field type checks: PASS' 
