#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
seed="$root/bin/s_seed"
stage0="$root/src/cmd/compile/stage0/stage0.c"
seed_main="$root/src/cmd/compile/seed/s_seed.c"
seed_analyzer="$root/src/cmd/compile/seed/semantic/analyzer.c"
modular_main="$root/src/cmd/compile/modular_build_main.s"
backend="$root/src/cmd/compile/internal/backend_elf64.s"
semantic="$root/src/cmd/compile/internal/semantic.s"
stage1_authority_report="${STAGE1_BUILD_AUTHORITY_REPORT:-"$root/.bootstrap/modular/stage1-build-authority-report.txt"}"

tmp="${TMPDIR:-/tmp}/b6.7.3d-authority-handoff.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

bash "$root/misc/scripts/check-b6.7.3d-qualified-call-e2e-routing.sh" >"$tmp/routing.report"
sh "$root/misc/scripts/stage1-build-authority-check.sh" >"$tmp/stage1-build.report"

current_authority=UNKNOWN
if grep -qx 'seed-binary-uses-c-semantic=YES' "$tmp/routing.report" &&
   grep -qx 'seed-member-call-method-path=YES' "$tmp/routing.report"; then
    current_authority="bin/s_seed -> seed_compile_source_text -> C parser -> C semantic analyzer"
fi

seed_compile_edge=MISSING
if rg -q -F "bool seed_compile_source_text(const char *source_text, FILE *output, compile_error *err)" "$seed_main" &&
   rg -q -F "if (!semantic_analyze(parsed.root, err))" "$seed_main"; then
    seed_compile_edge="$seed_main:65 -> seed_compile_source_text -> semantic_analyze(parsed.root, err)"
fi

seed_semantic_edge=MISSING
if rg -q -F "if (!analyze_expr(ctx, member->as.member_expr.object, &lhs_type))" "$seed_analyzer" &&
   rg -q -F "\"type '%s' has no method '%s'\"" "$seed_analyzer"; then
    seed_semantic_edge="$seed_analyzer:1205 -> analyze member callee receiver before method lookup"
fi

canonical_resolver_edge=MISSING
if rg -q -F "lookup_qualified_functions(functions, qualified_package, qualified_name)" "$semantic"; then
    canonical_resolver_edge="$semantic:1518 -> lookup_qualified_functions(functions, qualified_package, qualified_name)"
fi

canonical_build_candidate=MISSING
if grep -q '^canonical-build-candidate=' "$tmp/stage1-build.report"; then
    canonical_build_candidate=$(grep '^canonical-build-candidate=' "$tmp/stage1-build.report" | sed 's/^canonical-build-candidate=//')
fi

canonical_backend_edge=MISSING
if grep -q '^backend-entry=' "$tmp/stage1-build.report"; then
    canonical_backend_edge=$(grep '^backend-entry=' "$tmp/stage1-build.report" | sed 's/^backend-entry=//')
fi

canonical_parser_edge=MISSING
if grep -q '^canonical-parser-entry=' "$tmp/stage1-build.report"; then
    canonical_parser_edge=$(grep '^canonical-parser-entry=' "$tmp/stage1-build.report" | sed 's/^canonical-parser-entry=//')
fi

canonical_semantic_edge=MISSING
if grep -q '^semantic-entry=' "$tmp/stage1-build.report"; then
    canonical_semantic_edge=$(grep '^semantic-entry=' "$tmp/stage1-build.report" | sed 's/^semantic-entry=//')
fi

replacement_edge=MISSING
if grep -q '^replacement-edge=' "$tmp/stage1-build.report"; then
    replacement_edge=$(grep '^replacement-edge=' "$tmp/stage1-build.report" | sed 's/^replacement-edge=//')
fi

handoff_edge=MISSING
authority_handoff_required=YES
if [ "$replacement_edge" != MISSING ]; then
    handoff_edge="$replacement_edge"
fi

classification=AUTHORITY_HANDOFF_EDGE_IDENTIFIED
if [ "$current_authority" = UNKNOWN ] || [ "$handoff_edge" = MISSING ]; then
    classification=AUTHORITY_HANDOFF_EDGE_NOT_PROVEN
fi

echo "B6.7.3d Authority Handoff Edge Audit"
echo "current-authority=$current_authority"
echo "current-compile-edge=$seed_compile_edge"
echo "current-semantic-edge=$seed_semantic_edge"
echo "desired-authority=explicit Stage0/root -> produce/launch canonical Stage1 -> canonical parser -> canonical semantic -> MIR -> backend"
echo "canonical-build-candidate=$canonical_build_candidate"
echo "canonical-backend-edge=$canonical_backend_edge"
echo "canonical-parser-edge=$canonical_parser_edge"
echo "canonical-semantic-edge=$canonical_semantic_edge"
echo "canonical-qualified-resolver-edge=$canonical_resolver_edge"
echo "handoff-edge=$handoff_edge"
echo "C-seed-qualified-resolution-extension=FORBIDDEN"
echo "canonical-resolver-rework=FORBIDDEN"
echo "authority-handoff-required=$authority_handoff_required"
echo "routing-gap=$(grep '^classification=' "$tmp/routing.report" | sed 's/^classification=//')"
echo "classification=$classification"
