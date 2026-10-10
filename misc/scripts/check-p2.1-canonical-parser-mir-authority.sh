#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler="$root/bin/s_compiler"
main_file="$root/src/cmd/compile/internal/compiler/compiler_main.s"
emit_file="$root/src/cmd/compile/middlend/mir/compiler_emit.s"

fail() {
    echo "p2.1 canonical parser mir authority: $*" >&2
    exit 1
}

require_source() {
    file=$1
    needle=$2
    label=$3
    if ! grep -Fq -- "$needle" "$file"; then
        fail "missing $label in ${file#$root/}: $needle"
    fi
}

reject_source() {
    file=$1
    needle=$2
    label=$3
    if grep -Fq -- "$needle" "$file"; then
        fail "unexpected $label in ${file#$root/}: $needle"
    fi
}

[ -x "$compiler" ] || fail "missing executable compiler: $compiler"

require_source "$main_file" 'compiler_emit_canonical_mir(source)' 'canonical --emit-mir dispatch'
require_source "$emit_file" 'func compiler_emit_canonical_mir(string source) string' 'canonical MIR producer'
require_source "$emit_file" 'parse_source(source)' 'canonical parser call'
require_source "$emit_file" 'check_source_file(parsed' 'semantic gate call'
require_source "$emit_file" 'lower_main_to_mir(parsed' 'MIR lowering call using parser AST'
require_source "$emit_file" 'dump_graph(graph)' 'structured mir_graph dump'

work=$(mktemp -d "${TMPDIR:-/tmp}/s-p2.1-mir.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/valid.s" <<'SRC'
package main

func main() int {
    return 0
}
SRC

"$compiler" --emit-mir "$work/valid.s" "$work/valid.mir" >"$work/valid.out" 2>"$work/valid.err" ||
    fail "valid source failed to emit MIR: $(cat "$work/valid.err")"

require_source "$work/valid.mir" 'mir main blocks=1 entry=0 exit=0' 'structured MIR graph header'
require_source "$work/valid.mir" 'bb0(entry)' 'canonical basic block label'
require_source "$work/valid.mir" 'term=return' 'canonical return terminator'

cat >"$work/syntax_error.s" <<'SRC'
package main

func main() int {
    return 0
SRC

if "$compiler" --emit-mir "$work/syntax_error.s" "$work/syntax_error.mir" >"$work/syntax.out" 2>"$work/syntax.err"; then
    fail "syntax error unexpectedly emitted MIR"
fi
if [ -s "$work/syntax_error.mir" ]; then
    fail "syntax error produced MIR output"
fi

cat >"$work/type_error.s" <<'SRC'
package main

func main() int {
    return "not int"
}
SRC

if "$compiler" --emit-mir "$work/type_error.s" "$work/type_error.mir" >"$work/type.out" 2>"$work/type.err"; then
    fail "semantic type error unexpectedly emitted MIR"
fi
if [ -s "$work/type_error.mir" ]; then
    fail "semantic type error produced MIR output"
fi

emit_c="$work/valid.c"
"$compiler" --emit-c "$work/valid.s" "$emit_c" >"$work/emit-c.out" 2>"$work/emit-c.err" ||
    fail "--emit-c regression failed: $(cat "$work/emit-c.err")"
require_source "$emit_c" 'int main' '--emit-c output'

echo "P2.1.canonical-parser-entry=PROVEN"
echo "P2.1.real-ast-produced=YES"
echo "P2.1.semantic-check=PASS"
echo "P2.1.lower-main-to-mir=PASS"
echo "P2.1.real-mir-graph-produced=YES"
echo "P2.1.synthetic-mir=NO"
echo "P2.1.emit-c-regression=PASS"
echo "P2.1.status=PASS PROVEN"
