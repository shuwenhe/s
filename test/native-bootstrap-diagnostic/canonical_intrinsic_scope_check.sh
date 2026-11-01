#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-intrinsic-scope.XXXXXX)
trap 'rm -rf "$work"' EXIT
cat > "$work/apis.s" <<'S'
package first
extern "intrinsic" func __host_slice(string source, int start, int end) string
package second
extern "intrinsic" func __host_slice(string source, int start, int end) string
S
cat > "$work/main.s" <<'S'
package main
extern "intrinsic" func __host_slice(string source, int start, int end) string
func main() int { part := __host_slice("answer", 1, 4); return len(part) + 39 }
S
"$compiler" --compile-unit "$work/main.sasm" "$work/apis.s" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
sed '/^extern /d' "$work/main.s" > "$work/ambiguous.s"
printf preserve > "$work/rejected.sasm"
if "$compiler" --compile-unit "$work/rejected.sasm" "$work/apis.s" "$work/ambiguous.s" > "$work/rejected.log" 2>&1; then
    echo 'undeclared ambiguous intrinsic accepted' >&2; exit 1
fi
grep -q 'canonical semantic:' "$work/rejected.log" || { cat "$work/rejected.log"; exit 1; }
test "$(cat "$work/rejected.sasm")" = preserve
echo 'local intrinsic contracts resolve across packages; missing local contract remains rejected: PASS'
