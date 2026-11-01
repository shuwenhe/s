#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-standalone-reachability.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/unused.s" <<'S'
package main
extern "intrinsic" func unsupported_native_service(int value) int
func unused() int { return unsupported_native_service(3) }
func unused_marker() string { return "/bin/s_seed" }
func helper() int { return 42 }
func main() int { eprintln("live literal"); return helper() }
S
"$root/bin/s_seed" "$work/unused.s" "$work/unused.ir"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/unused.ir" "$work/program"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/program"
status=0; "$work/program" || status=$?
test "$status" -eq 42
if nm "$work/program" | grep -q 's_fn_unused'; then
    echo 'unreachable function retained in native executable' >&2; exit 1
fi
sed 's/return helper()/return unused()/' "$work/unused.s" > "$work/reachable.s"
"$root/bin/s_seed" "$work/reachable.s" "$work/reachable.ir"
if S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/reachable.ir" "$work/rejected" > "$work/log" 2>&1; then
    echo 'reachable missing intrinsic silently discarded' >&2; exit 1
fi
grep -q 'unsupported_native_service' "$work/log"
test ! -e "$work/rejected"
echo 'standalone function reachability and unresolved-call rejection: PASS'
