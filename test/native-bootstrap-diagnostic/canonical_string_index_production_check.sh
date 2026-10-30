#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-string-index.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
counter := 0
struct Text { string value }
func next() int { counter = counter + 1; return counter }
func main() int {
    text := "ABC"
    if text[next()] != "B"[0] || counter != 1 { return 1 }
    if text[-1] != ""[0] || text[3] != ""[0] { return 2 }
    empty := Text {}
    if empty.value[0] != ""[0] { return 3 }
    if "é"[0] == "é"[1] { return 4 }
    return 42
}
S
"$compiler" --compile-unit "$work/main.sasm" "$work/main.s"
"$compiler" --emit-bin "$work/main.sasm" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'native string byte indexing, bounds, default strings and single evaluation: PASS'
