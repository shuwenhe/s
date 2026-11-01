#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-declaration-kind.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "declaration kind artifacts: $work" >&2; fi' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root,work=map(Path,sys.argv[1:]); base=root/'src/cmd/compile/internal'
semantic=(base/'semantic/semantic.s').read_text()
def section(start,end): return semantic[semantic.index(start):semantic.index(end,semantic.index(start)+1)]
(work/'semantic.s').write_text('package compile.internal.semantic\n'+section('enum declaration_kind {','struct struct_binding {')+section('struct declaration_ref {','struct semantic_result {'))
mono=(base/'mono/monomorphization.s').read_text();start=mono.index('func find_declaration_ref_for_item(');end=mono.index('\nstruct ',start)
# The real function reads only this field of its production context.
(work/'mono.s').write_text('package compile.internal.mono\nimport "compile.internal.semantic"\nstruct mono_context { compile.internal.semantic.declaration_ref[] declarations }\n'+mono[start:end])
PY
cat > "$work/main.s" <<'S'
package main
import ( "compile.internal.semantic"; "compile.internal.mono" )
func validate() () {
    function_ref := compile.internal.semantic.declaration_ref { package_path: "function.pkg", kind: compile.internal.semantic.declaration_kind.function_kind, path: "Same" }
    struct_ref := compile.internal.semantic.declaration_ref { package_path: "struct.pkg", kind: compile.internal.semantic.declaration_kind.struct_kind, path: "Same" }
    method_ref := compile.internal.semantic.declaration_ref { package_path: "method.pkg", kind: compile.internal.semantic.declaration_kind.method_kind, path: "Same" }
    ctx := compile.internal.mono.mono_context { declarations: [function_ref, struct_ref, method_ref] }
    f := compile.internal.mono.find_declaration_ref_for_item(ctx, "function", "Same")
    s := compile.internal.mono.find_declaration_ref_for_item(ctx, "struct", "Same")
    m := compile.internal.mono.find_declaration_ref_for_item(ctx, "method", "Same")
    if f.package_path != "function.pkg" || s.package_path != "struct.pkg" || m.package_path != "method.pkg" { panic("wrong declaration identity") }
    missing := compile.internal.mono.find_declaration_ref_for_item(ctx, "function", "Missing")
    if missing.package_path != "" || missing.path != "Missing" || missing.kind != compile.internal.semantic.declaration_kind.function_kind { panic("wrong fallback declaration") }
}
func main() int { validate(); return 42 }
S
"$root/bin/s_seed" --compile-native-unit "$work/main.ir" "$work/semantic.s" "$work/mono.s" "$work/main.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/main.ir" "$work/main"
status=0; "$work/main" || status=$?
test "$status" -eq 42
echo 'production declaration lookup uses typed enum owners for function/struct/method/fallback: PASS'
