#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-frontend-lexer-native.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
cat > "$work/main.s" <<'S'
package main
import "compile.internal.parser"
func main() int {
    text := compile.internal.parser.frontend_lexer_slice("answer", 1, 4)
    if text != "nsw" { return 1 }
    if !compile.internal.parser.frontend_is_letter("a") { return 2 }
    if !compile.internal.parser.frontend_is_digit("3") { return 3 }
    if compile.internal.parser.frontend_is_digit(".") { return 4 }
    return 42
}

S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$root/src/option/option.s" "$root/src/result/result.s" "$root/src/prelude/prelude.s" "$root/src/cmd/compile/internal/parser/frontend_lexer.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
sh "$root/misc/scripts/verify_true_selfhost.sh" "$work/main"
status=0; timeout 10 "$work/main" || status=$?
test "$status" -eq 42
echo 'frontend lexer: native module borrow checks, intrinsic slice and character predicates: PASS'
