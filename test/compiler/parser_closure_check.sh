#!/usr/bin/env bash
# Parser closure must check build inputs without requiring their dependencies.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-parser-closure-test.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
make -s -C "$root" seed-compiler-bin
fixture="$work/source root"
mkdir -p "$fixture/bin" "$fixture/src"
ln -s "$root/bin/s_seed" "$fixture/bin/s_seed"
cat > "$fixture/src/dependent.s" <<'SRC'
package example
func first(external_record value) int {
    return value.items[0]
}
SRC
printf '%s\n' 'src/dependent.s' > "$fixture/.parser-closure-manifest"

expect_pass() {
    if ! bash "$root/script/canonical-parser-closure-check.sh" "$fixture" > "$work/output" 2>&1; then
        cat "$work/output" >&2
        echo 'parser closure rejected syntactically valid source' >&2
        exit 1
    fi
    grep -q 'RESULT: PASS' "$work/output"
    grep -Eq 'Files parsed:[[:space:]]+1$' "$work/output"
}

expect_fail() {
    if bash "$root/script/canonical-parser-closure-check.sh" "$fixture" > "$work/output" 2>&1; then
        cat "$work/output" >&2
        echo "parser closure accepted $1" >&2
        exit 1
    fi
}

expect_pass

# The default closure comes from the same Make variable as the compiler build.
rm "$fixture/.parser-closure-manifest"
printf 'compiler-source-list:\n\t@printf "%%s\\n" src/dependent.s\n' > "$fixture/makefile"
expect_pass

printf '%s\n' 'src/missing.s' > "$fixture/.parser-closure-manifest"
expect_fail 'a missing required source'
grep -q 'src/missing.s' "$work/output"

: > "$fixture/.parser-closure-manifest"
expect_fail 'an empty source closure'

printf '%s\n' 'src/dependent.s' > "$fixture/.parser-closure-manifest"
printf 'package example\nfunc broken( {\n' > "$fixture/src/dependent.s"
expect_fail 'invalid syntax'
grep -q 'src/dependent.s' "$work/output"

echo 'parser closure regression passed'
