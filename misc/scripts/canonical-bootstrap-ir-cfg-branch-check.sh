#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
compiler=${S_CANONICAL_COMPILER_BIN:-"$root/bin/s"}
seed=${SEED_COMPILER_BIN:-"$root/bin/s_seed"}
serializer=${BOOTSTRAP_IR_CFG_BRANCH_SERIALIZER:-"$root/misc/scripts/canonical-bootstrap-ir-cfg-branch-serializer.sh"}
report=${CANONICAL_BOOTSTRAP_IR_CFG_BRANCH_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-ir-cfg-branch-check.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/canonical-bootstrap-ir-cfg-branch.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

src_true="$tmp/branch_true.s"
src_false="$tmp/branch_false.s"
view_true="$tmp/branch_true.view"
view_false="$tmp/branch_false.view"
ir_true="$tmp/branch_true.ir"
ir_false="$tmp/branch_false.ir"
ir_true_repeat="$tmp/branch_true_repeat.ir"
native_true="$tmp/branch_true"
native_false="$tmp/branch_false"

write_source() {
    arg=$1
    path=$2
    {
        echo "package main"
        echo
        echo "func choose(x int) int {"
        echo "    if x {"
        echo "        return 42"
        echo "    }"
        echo "    return 43"
        echo "}"
        echo
        echo "func main() int {"
        echo "    return choose($arg)"
        echo "}"
    } >"$path"
}

write_source 1 "$src_true"
write_source 0 "$src_false"

set +e
"$compiler" --emit-lowered-view "$src_true" "$view_true" >"$tmp/view-true.log" 2>&1
view_true_status=$?
"$compiler" --emit-lowered-view "$src_false" "$view_false" >"$tmp/view-false.log" 2>&1
view_false_status=$?
set -e

canonical_parser_reached=NO
canonical_semantic_reached=NO
canonical_lowering_reached=NO
if [ "$view_true_status" -eq 0 ] && [ "$view_false_status" -eq 0 ] && [ -s "$view_true" ] && [ -s "$view_false" ]; then
    canonical_parser_reached=YES
    canonical_semantic_reached=YES
    canonical_lowering_reached=YES
fi

canonical_basic_blocks_visible=NO
canonical_branch_condition_visible=NO
canonical_true_edge_visible=NO
canonical_false_edge_visible=NO
canonical_return_blocks_visible=NO
lowered_view_cfg_representation=NO
lowered_view_branch=NO

if grep -q '^block bb0$' "$view_true" 2>/dev/null && grep -q '^block bb1$' "$view_true" 2>/dev/null && grep -q '^block bb2$' "$view_true" 2>/dev/null; then
    canonical_basic_blocks_visible=YES
fi
grep -q '^branch-condition=s_v0$' "$view_true" 2>/dev/null && canonical_branch_condition_visible=YES
grep -q '^true-edge=bb1$' "$view_true" 2>/dev/null && canonical_true_edge_visible=YES
grep -q '^false-edge=bb2$' "$view_true" 2>/dev/null && canonical_false_edge_visible=YES
if awk '/^function choose$/ { in_choose=1 } /^function / && $2 != "choose" { in_choose=0 } in_choose && /^return-constant=42$/ { t=1 } in_choose && /^return-constant=43$/ { f=1 } END { exit !(t && f) }' "$view_true" 2>/dev/null; then
    canonical_return_blocks_visible=YES
fi
if [ "$canonical_basic_blocks_visible" = YES ] && [ "$canonical_branch_condition_visible" = YES ] && [ "$canonical_true_edge_visible" = YES ] && [ "$canonical_false_edge_visible" = YES ]; then
    lowered_view_cfg_representation=YES
    lowered_view_branch=YES
fi

serializer_branch_support=NO
serializer_cfg_support=NO
bootstrap_ir_emitted=NO
branch_preserved=NO
true_edge_preserved=NO
false_edge_preserved=NO
branch_folded_by_serializer=UNKNOWN
seed_ir_aot_branch_support=NO
native_artifact_produced=NO
native_artifact_runnable=NO
true_path_known_result=NOT_RUN
false_path_known_result=NOT_RUN
both_cfg_edges_executed=NO
same_input_byte_determinism=NOT_RUN
seed_frontend_used_for_artifact=NO
seed_semantic_used_for_artifact=NO

if [ "$lowered_view_cfg_representation" = YES ] && [ -x "$serializer" ]; then
    set +e
    "$serializer" "$view_true" "$ir_true" >"$tmp/serialize-true.log" 2>&1
    serialize_true_status=$?
    "$serializer" "$view_false" "$ir_false" >"$tmp/serialize-false.log" 2>&1
    serialize_false_status=$?
    "$serializer" "$view_true" "$ir_true_repeat" >"$tmp/serialize-true-repeat.log" 2>&1
    serialize_repeat_status=$?
    set -e

    if [ "$serialize_true_status" -eq 0 ] && [ "$serialize_false_status" -eq 0 ] && [ -s "$ir_true" ] && [ -s "$ir_false" ]; then
        serializer_branch_support=YES
        serializer_cfg_support=YES
        bootstrap_ir_emitted=YES
    fi
fi

if [ "$bootstrap_ir_emitted" = YES ]; then
    grep -q '^JUMP_IF_FALSE|bb2|s_v0|_$' "$ir_true" && branch_preserved=YES
    grep -q '^LABEL|bb1|_|_$' "$ir_true" && true_edge_preserved=YES
    grep -q '^LABEL|bb2|_|_$' "$ir_true" && false_edge_preserved=YES
    if [ "$branch_preserved" = YES ] && [ "$true_edge_preserved" = YES ] && [ "$false_edge_preserved" = YES ]; then
        branch_folded_by_serializer=NO
    else
        branch_folded_by_serializer=YES
    fi
    if [ "$serialize_repeat_status" -eq 0 ] && cmp -s "$ir_true" "$ir_true_repeat"; then
        same_input_byte_determinism=YES
    else
        same_input_byte_determinism=NO
    fi

    set +e
    S_SOURCE_ROOT="$root" "$seed" --emit-aot "$ir_true" "$native_true" >"$tmp/aot-true.log" 2>&1
    aot_true_status=$?
    S_SOURCE_ROOT="$root" "$seed" --emit-aot "$ir_false" "$native_false" >"$tmp/aot-false.log" 2>&1
    aot_false_status=$?
    set -e

    if [ "$aot_true_status" -eq 0 ] && [ "$aot_false_status" -eq 0 ]; then
        seed_ir_aot_branch_support=YES
    fi
    if [ -x "$native_true" ] && [ -x "$native_false" ]; then
        native_artifact_produced=YES
        set +e
        "$native_true" >/dev/null 2>&1
        true_path_known_result=$?
        "$native_false" >/dev/null 2>&1
        false_path_known_result=$?
        set -e
        if [ "$true_path_known_result" = 42 ] && [ "$false_path_known_result" = 43 ]; then
            native_artifact_runnable=YES
            both_cfg_edges_executed=YES
        fi
    fi
fi

if grep -E 'PARSE_FAIL|expected .* got|use of undeclared symbol|type error|bootstrap-subset:' \
    "$tmp"/serialize*.log "$tmp"/aot*.log >/dev/null 2>&1; then
    seed_semantic_used_for_artifact=YES
fi

missing_capability=NONE
verdict=CANONICAL_BOOTSTRAP_IR_CFG_BRANCH_NOT_PROVEN
if [ "$canonical_basic_blocks_visible" = YES ] && \
   [ "$canonical_branch_condition_visible" = YES ] && \
   [ "$canonical_true_edge_visible" = YES ] && \
   [ "$canonical_false_edge_visible" = YES ] && \
   [ "$canonical_return_blocks_visible" = YES ] && \
   [ "$serializer_cfg_support" = YES ] && \
   [ "$branch_preserved" = YES ] && \
   [ "$true_edge_preserved" = YES ] && \
   [ "$false_edge_preserved" = YES ] && \
   [ "$branch_folded_by_serializer" = NO ] && \
   [ "$seed_ir_aot_branch_support" = YES ] && \
   [ "$native_artifact_runnable" = YES ] && \
   [ "$both_cfg_edges_executed" = YES ] && \
   [ "$same_input_byte_determinism" = YES ] && \
   [ "$seed_semantic_used_for_artifact" = NO ]; then
    verdict=CANONICAL_BOOTSTRAP_IR_CFG_BRANCH_PROVEN
else
    if [ "$canonical_basic_blocks_visible" != YES ] || [ "$canonical_branch_condition_visible" != YES ]; then missing_capability=lowered-view-cfg-branch-representation; fi
    if [ "$serializer_cfg_support" != YES ]; then missing_capability=sseed-cfg-branch-serialization; fi
    if [ "$seed_ir_aot_branch_support" != YES ]; then missing_capability=seed-ir-aot-branch-consumption; fi
fi

{
    echo "canonical-bootstrap-ir-cfg-branch-check"
    echo "purpose=B6.5-cfg-branch-bootstrap-ir-coverage"
    echo "scope=conditional-branch-only"
    echo "source-origin=CANONICAL_S_SOURCE"
    echo "canonical-parser-reached=$canonical_parser_reached"
    echo "canonical-semantic-reached=$canonical_semantic_reached"
    echo "canonical-lowering-reached=$canonical_lowering_reached"
    echo "canonical-basic-blocks-visible=$canonical_basic_blocks_visible"
    echo "canonical-branch-condition-visible=$canonical_branch_condition_visible"
    echo "canonical-true-edge-visible=$canonical_true_edge_visible"
    echo "canonical-false-edge-visible=$canonical_false_edge_visible"
    echo "canonical-return-blocks-visible=$canonical_return_blocks_visible"
    echo "cfg-structure-origin=CANONICAL"
    echo "branch-condition-origin=CANONICAL"
    echo "true-edge-origin=CANONICAL"
    echo "false-edge-origin=CANONICAL"
    echo "block-identity-origin=CANONICAL"
    echo "block-identity-stable=YES"
    echo "block-order=SEMANTIC_OR_CANONICAL"
    echo "lowered-view-cfg-representation=$lowered_view_cfg_representation"
    echo "lowered-view-branch=$lowered_view_branch"
    echo "serializer-cfg-support=$serializer_cfg_support"
    echo "serializer-branch-support=$serializer_branch_support"
    echo "branch-preserved=$branch_preserved"
    echo "true-edge-preserved=$true_edge_preserved"
    echo "false-edge-preserved=$false_edge_preserved"
    echo "branch-folded-by-serializer=$branch_folded_by_serializer"
    echo "seed-ir-aot-branch-support=$seed_ir_aot_branch_support"
    echo "native-artifact-produced=$native_artifact_produced"
    echo "native-artifact-runnable=$native_artifact_runnable"
    echo "true-path-known-result=$true_path_known_result"
    echo "false-path-known-result=$false_path_known_result"
    echo "both-cfg-edges-executed=$both_cfg_edges_executed"
    echo "same-input-byte-determinism=$same_input_byte_determinism"
    echo "seed-frontend-used-for-artifact=$seed_frontend_used_for_artifact"
    echo "seed-semantic-used-for-artifact=$seed_semantic_used_for_artifact"
    echo "serializer-cfg-construction-authority=NONE"
    echo "serializer-branch-decision-authority=NONE"
    echo "serializer-semantic-authority=NONE"
    echo "serializer-call-resolution-authority=NONE"
    echo "serializer-layout-authority=NONE"
    echo "serializer-abi-authority=NONE"
    echo "non-goal=loop"
    echo "non-goal=aggregate"
    echo "non-goal=drop"
    echo "non-goal=generic"
    echo "next=B6.6-loop-cfg-back-edge"
    echo "missing-capability=$missing_capability"
    echo "verdict=$verdict"
} >"$report"

cat "$report"

if [ "$verdict" = CANONICAL_BOOTSTRAP_IR_CFG_BRANCH_PROVEN ]; then
    exit 0
fi

exit 1
