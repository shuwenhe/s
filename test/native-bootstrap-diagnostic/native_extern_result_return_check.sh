#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-extern-result-return.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/input.s" <<'S'
package main
import "std.result"
struct failure { string message }
func read_text() (string, failure) { host_read() }
func run_command() ((), failure) { host_run() }
extern "intrinsic" func host_read() (string, failure)
extern "intrinsic" func host_run() ((), failure)
func main() int { return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/program.ir" "$root/src/result/result.s" "$work/input.s"
sed 's/func read_text() (string, failure)/func read_text() (int, failure)/' "$work/input.s" > "$work/wrong.s"
printf 'preserve\n' > "$work/output"
cp "$work/output" "$work/saved"
if "$root/bin/s_seed" --compile-native-unit "$work/output" "$root/src/result/result.s" "$work/wrong.s" > "$work/wrong.log" 2>&1; then
    echo 'incompatible extern result accepted by wrapper' >&2; exit 1
fi
cmp "$work/output" "$work/saved"
grep -Eq 'does not return on all paths|tuple return value matches neither success nor error type' "$work/wrong.log"
echo 'extern tuple return and native wrapper share result identity: PASS'
