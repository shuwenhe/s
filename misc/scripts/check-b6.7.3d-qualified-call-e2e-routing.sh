#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
seed="${SEED_COMPILER_BIN:-"$root/bin/s_seed"}"
semantic="$root/src/cmd/compile/internal/semantic.s"
backend="$root/src/cmd/compile/internal/backend_elf64.s"
seed_analyzer="$root/src/cmd/compile/seed/semantic/analyzer.c"
makefile="$root/Makefile"

tmp="${TMPDIR:-/tmp}/b6.7.3d-qualified-call-routing.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

if [ ! -x "$seed" ]; then
    make -C "$root" seed-compiler-bin >/dev/null
fi

cat >"$tmp/std-env-args.s" <<'SRC'
package test
import (
    "std.env"
)
func main() int {
    args := std.env.args()
    return 0
}
SRC

set +e
S_SOURCE_ROOT="$root" "$seed" "$tmp/std-env-args.s" "$tmp/std-env-args.ir" >"$tmp/seed.log" 2>&1
status=$?
set -e

first_line="$(sed -n '1p' "$tmp/seed.log")"

canonical_resolver_present=NO
if rg -q -F "lookup_qualified_functions(functions, qualified_package, qualified_name)" "$semantic" &&
   rg -q -F "qualified_expr_path(value.callee.value)" "$semantic"; then
    canonical_resolver_present=YES
fi

canonical_backend_semantic_edge=NO
if rg -q -F "compile.internal.semantic.check_source_file(combined, source)" "$backend"; then
    canonical_backend_semantic_edge=YES
fi

seed_binary_uses_c_semantic=NO
if rg -q -F "src/cmd/compile/seed/semantic/analyzer.c" "$makefile"; then
    seed_binary_uses_c_semantic=YES
fi

seed_member_call_method_path=NO
if rg -q -F "if (!analyze_expr(ctx, member->as.member_expr.object, &lhs_type))" "$seed_analyzer" &&
   rg -q -F "\"type '%s' has no method '%s'\"" "$seed_analyzer"; then
    seed_member_call_method_path=YES
fi

old_any_blocker=NO
if grep -q "type 'any' has no method 'args'" "$tmp/seed.log"; then
    old_any_blocker=YES
fi

canonical_semantic_reached=NO
qualified_call_branch_reached=NO
qualified_binding_found=NO
runtime_backend_reached=NO
classification=RED_EXPECTED
first_divergence="unknown"

if [ "$seed_binary_uses_c_semantic" = YES ] && [ "$old_any_blocker" = YES ]; then
    first_divergence="real-closure-probe uses bin/s_seed C semantic analyzer before canonical compile.internal.semantic resolver"
    classification=AUTHORITY_ROUTING_GAP
elif [ "$old_any_blocker" = NO ] && [ "$status" -ne 0 ]; then
    first_divergence="old any.args blocker moved; inspect next semantic/consumer edge"
    classification=NEXT_BLOCKER_DISCOVERED
elif [ "$status" -eq 0 ]; then
    canonical_semantic_reached=UNKNOWN
    qualified_call_branch_reached=UNKNOWN
    qualified_binding_found=UNKNOWN
    runtime_backend_reached=YES
    first_divergence=NONE
    classification=B6.7.3d_UNEXPECTED_GREEN
fi

echo "B6.7.3d Qualified Call E2E / Authority Routing"
echo "probe=std.env.args()"
echo "actual-binary=$seed"
echo "real-probe-status=$status"
echo "real-probe-first-line=$first_line"
echo "canonical-resolver-present=$canonical_resolver_present"
echo "canonical-backend-semantic-edge=$canonical_backend_semantic_edge"
echo "seed-binary-uses-c-semantic=$seed_binary_uses_c_semantic"
echo "seed-member-call-method-path=$seed_member_call_method_path"
echo "canonical-parser-reached=$canonical_semantic_reached"
echo "canonical-semantic-reached=$canonical_semantic_reached"
echo "qualified-call-branch-reached=$qualified_call_branch_reached"
echo "qualified-lookup-key=(std.env,args)"
echo "qualified-binding-found=$qualified_binding_found"
echo "runtime/backend-reached=$runtime_backend_reached"
echo "first-divergence=$first_divergence"
echo "classification=$classification"
