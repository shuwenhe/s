#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-resolved-builtin-names.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/library.s" <<'S'
package utility
func len(int value) int { return value }
func push(int value, int step) int { return value + step }
func set(int value) int { return value }
S
cat > "$work/main.s" <<'S'
package main
import "utility"
func main() int { return utility.len(utility.push(39, 1)) + utility.set(2) }
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s" "$work/library.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'resolved qualified functions named len/push/set bypass builtin method lowering: PASS'
