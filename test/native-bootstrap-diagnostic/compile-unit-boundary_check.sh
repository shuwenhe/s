#!/usr/bin/env bash
set -euo pipefail

root=${S_SOURCE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
seed=${S_SEED:-$root/bin/s_seed}
work=$(mktemp -d "${TMPDIR:-/tmp}/s-unit-boundary.XXXXXX")
printf 'compile-unit evidence: %s\n' "$work"

cat >"$work/main.s" <<'SOURCE'
package boundary
func main() int { return answer() }
SOURCE
cat >"$work/answer.s" <<'SOURCE'
package boundary
func answer() int { return 42 }
SOURCE
"$seed" --compile-unit "$work/same.ir" "$work/main.s" "$work/answer.s" >"$work/same.log" 2>&1
"$seed" --emit-bin "$work/same.ir" "$work/same" >>"$work/same.log" 2>&1
status=0
"$work/same" || status=$?
test "$status" -eq 42
printf 'PASS: same-package cross-file call returns 42\n'

cat >"$work/loop.s" <<'SOURCE'
package boundary
func loop() int {
    for { break }
    return 7
}
SOURCE
if ! "$seed" --dump-ast "$work/loop.s" "$work/loop.ast" >"$work/loop.log" 2>&1; then
    cat "$work/loop.log" >&2
    exit 1
fi
"$seed" --compile-unit "$work/loop.ir" "$work/loop.s" "$work/answer.s" >"$work/loop-unit.log" 2>&1
printf 'PASS: infinite-loop body does not consume the next file\n'

expect_failure() {
    local name=$1 source=$2 location=$3
    shift 3
    if "$seed" --compile-unit "$work/$name.ir" "$@" >"$work/$name.log" 2>&1; then
        printf 'FAIL: %s was accepted\n' "$name" >&2
        exit 1
    fi
    if ! grep -Fq "$source:$location" "$work/$name.log"; then
        cat "$work/$name.log" >&2
        printf 'FAIL: %s lost its source location\n' "$name" >&2
        exit 1
    fi
    test ! -s "$work/$name.ir"
}

# A file cannot borrow a closing brace from the next file.
printf 'package boundary\nfunc broken() int {\n' >"$work/open.s"
printf 'package boundary\n}\n' >"$work/close.s"
expect_failure open "$work/open.s" '3:1' "$work/open.s" "$work/close.s"
printf 'PASS: unclosed file is rejected at its own EOF\n'

printf 'package boundary\nfunc broken() int { return @ }\n' >"$work/illegal.s"
expect_failure illegal "$work/illegal.s" '2:28' "$work/main.s" "$work/illegal.s"
printf 'PASS: lexical diagnostic preserves the second file location\n'

printf 'package boundary\nfunc answer() int { return ) }\n' >"$work/syntax.s"
expect_failure syntax "$work/syntax.s" '2:28' "$work/main.s" "$work/syntax.s"
printf 'PASS: syntax diagnostic preserves the second file location\n'

printf 'package boundary\nfunc answer() int { return missing }\n' >"$work/semantic.s"
expect_failure semantic "$work/semantic.s" '2:28' "$work/main.s" "$work/semantic.s"
printf 'PASS: semantic diagnostic preserves the second file location\n'

printf 'package other\nfunc answer() int { return 99 }\n' >"$work/other.s"
expect_failure packages "$work/other.s" '1:1' "$work/main.s" "$work/other.s"
grep -Fq 'multi-package name resolution is not supported' "$work/packages.log"
printf 'PASS: unsupported cross-package resolution fails explicitly\n'

printf 'package boundary\npackage other\nfunc answer() int { return 99 }\n' >"$work/two-headers.s"
expect_failure headers "$work/two-headers.s" '2:1' "$work/main.s" "$work/two-headers.s"
printf 'PASS: one source file cannot contain two package headers\n'

# Import bindings must not leak from one source file into another.
cat >"$work/import.s" <<'SOURCE'
package boundary
use std.io.print as output
func answer() int { return 42 }
SOURCE
cat >"$work/leak.s" <<'SOURCE'
package boundary
func main() int { output(1); return 0 }
SOURCE
expect_failure imports "$work/import.s" '2:1' "$work/leak.s" "$work/import.s"
grep -Fq 'file-scoped imports are not supported' "$work/imports.log"
printf 'PASS: unsupported file-scoped imports fail explicitly\n'

printf 'compile-unit boundary regression: PASS\n'
