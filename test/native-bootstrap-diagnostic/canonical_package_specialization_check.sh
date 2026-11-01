#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-package-specialization.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/helper.s" <<'S'
package helper
func identity[T](T value) T { return value }
func increase(int value) int { return value + 2 }
S
cat > "$work/main.s" <<'S'
package main
import "helper"
func main() int { return increase(identity(40)) + helper.identity(0) }
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s" "$work/helper.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'qualified and unqualified imported generic calls share their declaration package: PASS'
