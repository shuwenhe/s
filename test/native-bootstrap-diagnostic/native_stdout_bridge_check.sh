#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-stdout.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import "std.io"
func validate() () {
    std.io.println("native")
    std.io.println("rope:" + "text")
    std.io.eprintln("diagnostic")
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/io/io.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
ulimit -c 0
status=0; "$work/main" > "$work/stdout" 2> "$work/stderr" || status=$?
test "$status" -eq 42
printf 'native\nrope:text\n' > "$work/expected-out"
printf 'diagnostic\n' > "$work/expected-err"
cmp "$work/stdout" "$work/expected-out"
cmp "$work/stderr" "$work/expected-err"
sed 's/ARG|"native"|/ARG|42|/' "$work/main.ir" > "$work/bad.ir"
printf preserve > "$work/output"
if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/bad.ir" "$work/output" > "$work/bad.log" 2>&1; then
 echo 'accepted non-string stdout argument' >&2; exit 1
fi
test "$(cat "$work/output")" = preserve
echo 'native std.io prints flat/rope strings to correct streams and rejects wrong types: PASS'
