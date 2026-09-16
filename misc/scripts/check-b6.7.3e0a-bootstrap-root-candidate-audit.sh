#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
entry_rel="src/cmd/compile/modular_build_main.s"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
report="$root/.bootstrap/modular/b6.7.3e0a-bootstrap-root-candidate-audit.txt"

tmp="${TMPDIR:-/tmp}/b6.7.3e0a-root.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$(dirname "$report")"

run_optional() {
    local label="$1"
    shift
    set +e
    "$@" >"$tmp/$label.report" 2>&1
    local status=$?
    set -e
    echo "$status" >"$tmp/$label.status"
}

field_from() {
    local file="$1"
    local key="$2"
    if [ -f "$file" ]; then
        awk -F= -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$file"
    else
        echo "UNKNOWN"
    fi
}

has_text() {
    local pattern="$1"
    shift
    rg -q -e "$pattern" "$root/$@" 2>/dev/null
}

status_bool() {
    if "$@"; then
        echo YES
    else
        echo NO
    fi
}

closure_count=0
closure_contains_entry=NO
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if grep -qx "$entry_rel" "$closure"; then
        closure_contains_entry=YES
    fi
fi

run_optional e3a bash "$root/misc/scripts/check-b6.7.3e3a-bootstrap-ir-generator-feasibility-audit.sh"
run_optional e2c bash "$root/misc/scripts/check-b6.7.3e2c-generated-c-producer-audit.sh"
run_optional root_candidates sh "$root/misc/scripts/bootstrap-root-candidate-audit.sh"
run_optional modular_root sh "$root/misc/scripts/modular_bootstrap_root_audit.sh" "$entry_rel" "$tmp/modular-root.report.out"

e3a_classification=$(field_from "$tmp/e3a.report" classification)
e2c_classification=$(field_from "$tmp/e2c.report" classification)
e2c_common_root=$(field_from "$tmp/e2c.report" common-root-if-red)

seed_present=NO
[ -x "$root/bin/s_seed" ] && seed_present=YES
s_compiler_present=NO
[ -x "$root/bin/s_compiler" ] && s_compiler_present=YES
s_wrapper_present=NO
[ -x "$root/bin/s" ] && s_wrapper_present=YES
s_darwin_present=NO
[ -x "$root/bin/s_darwin_arm64" ] && s_darwin_present=YES
modular_stage1_present=NO
[ -x "$root/.bootstrap/modular/s_modular-stage1" ] && modular_stage1_present=YES

checked_in_ir_count=$(find "$root" -path "$root/.git" -prune -o -path "$root/.bootstrap" -prune -o -name '*.ir' -type f -print | wc -l | tr -d ' ')
checked_in_ir_stage1=NO
[ -f "$root/src/cmd/compile/seed/stage1.ir" ] && checked_in_ir_stage1=YES
checked_in_ir_stage2=NO
[ -f "$root/src/cmd/compile/seed/stage2.ir" ] && checked_in_ir_stage2=YES

selfhost_source_present=NO
[ -f "$root/src/cmd/compile/selfhost/compiler.s" ] && selfhost_source_present=YES
selfhost_ladder_present=$(status_bool has_text 'stage2.ir|stage3.ir|bootstrap_three_stage|stage2.*stage3' src/cmd/compile/selfhost makefile src/cmd/dist)
slice_ladder_present=$(status_bool has_text 'bootstrap-slice|slice[0-9]' makefile test src/cmd/compile/selfhost)
convergence_gate_present=$(status_bool has_text 'stage2.*stage3|Stage2.*Stage3|cmp .*stage2.*stage3|bootstrap-convergence' makefile misc/scripts src/cmd/compile)

git_history_available=NO
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_history_available=YES
    git -C "$root" log --all --oneline --decorate --max-count=80 --grep='bootstrap\|selfhost\|stage\|compiler\|s_seed\|s_darwin' >"$tmp/history.log" 2>/dev/null || :
    git -C "$root" log --all --name-only --pretty=format: -- bin .bootstrap src/cmd/compile/selfhost src/cmd/compile/seed/stage1.ir src/cmd/compile/seed/stage2.ir 2>/dev/null |
        sed '/^$/d' | LC_ALL=C sort -u >"$tmp/history-assets.log" || :
else
    : >"$tmp/history.log"
    : >"$tmp/history-assets.log"
fi

history_signal_count=$(wc -l <"$tmp/history.log" | tr -d ' ')
history_asset_count=$(wc -l <"$tmp/history-assets.log" | tr -d ' ')

candidate_a_status=PARTIAL
candidate_a_reason=historical-selfhost-source-and-ladder-exist-but-target-selfhost-compiler-not-current-37-file-canonical-closure
if [ "$selfhost_source_present" != YES ]; then
    candidate_a_status=NOT_VIABLE
    candidate_a_reason=selfhost-source-missing
fi

candidate_b_status=PARTIAL
candidate_b_reason=bootstrap-snapshot-or-seed-ir-assets-exist-but-canonical-runtime-and-provenance-not-proven
if [ "$checked_in_ir_count" = 0 ]; then
    candidate_b_status=NOT_VIABLE_CURRENTLY
    candidate_b_reason=no-checked-in-bootstrap-snapshot-assets
fi

candidate_c_status=PARTIAL
candidate_c_reason=stage-or-slice-ladder-signals-exist-but-no-rung-proven-to-reach-current-canonical-closure
if [ "$selfhost_ladder_present" != YES ] && [ "$slice_ladder_present" != YES ]; then
    candidate_c_status=NOT_VIABLE_CURRENTLY
    candidate_c_reason=no-bootstrap-ladder-assets
fi

candidate_d_status=PARTIAL
candidate_d_reason=prebuilt-binaries-exist-but-current-canonical-closure-consumption-and-provenance-not-proven
if [ "$seed_present" != YES ] && [ "$s_compiler_present" != YES ] && [ "$s_wrapper_present" != YES ] && [ "$s_darwin_present" != YES ] && [ "$modular_stage1_present" != YES ]; then
    candidate_d_status=NOT_VIABLE_CURRENTLY
    candidate_d_reason=no-local-prebuilt-compiler-artifact
fi

best_candidate=NONE
recommended_next=BOOTSTRAP_TRUST_ROOT_DESIGN
classification=BOOTSTRAP_ROOT_NOT_SELECTED

if grep -q '^Decision=A-existing-compiler-minimal-gap' "$tmp/modular-root.report.out" 2>/dev/null; then
    best_candidate=historical-existing-compiler-minimal-gap
    recommended_next=PROBE_EXISTING_COMPILER_NEXT_FRONTIER
    classification=BOOTSTRAP_ROOT_CANDIDATE_FOUND_UNPROVEN
elif [ "$candidate_c_status" = PARTIAL ]; then
    best_candidate=bootstrap-ladder
    recommended_next=BOOTSTRAP_LADDER_RUNG_AUDIT
    classification=BOOTSTRAP_ROOT_CANDIDATE_FOUND_UNPROVEN
elif [ "$candidate_a_status" = PARTIAL ]; then
    best_candidate=historical-selfhost-compiler
    recommended_next=HISTORICAL_SELFHOST_ROOT_AUDIT
    classification=BOOTSTRAP_ROOT_CANDIDATE_FOUND_UNPROVEN
elif [ "$candidate_b_status" = PARTIAL ]; then
    best_candidate=frozen-bootstrap-snapshot
    recommended_next=FROZEN_BOOTSTRAP_SNAPSHOT_PROVENANCE_AUDIT
    classification=BOOTSTRAP_ROOT_CANDIDATE_FOUND_UNPROVEN
fi

{
    echo "B6.7.3e0a Bootstrap Root Candidate Audit"
    echo "purpose=read-only-audit-bootstrap-semantic-execution-root"
    echo "canonical-entry=$entry_rel"
    echo "canonical-closure=$closure"
    echo "canonical-closure-count=$closure_count"
    echo "canonical-closure-contains-entry=$closure_contains_entry"
    echo "root-problem=BOOTSTRAP_SEMANTIC_EXECUTION_ROOT_MISSING"
    echo "invariant-bootstrap-root=BOUNDED_FROZEN_AUDITABLE"
    echo "invariant-canonical-stage1-plus=PERMANENT_SEMANTIC_AUTHORITY"
    echo "invariant-permanent-dual-authority=FORBIDDEN"
    echo "prior-evidence-e3a=$e3a_classification"
    echo "prior-evidence-e2c=$e2c_classification"
    echo "prior-evidence-common-root=$e2c_common_root"
    echo "local-artifact=s_seed:$seed_present"
    echo "local-artifact=s_compiler:$s_compiler_present"
    echo "local-artifact=s-wrapper:$s_wrapper_present"
    echo "local-artifact=s_darwin_arm64:$s_darwin_present"
    echo "local-artifact=s_modular-stage1:$modular_stage1_present"
    echo "checked-in-ir-count=$checked_in_ir_count"
    echo "checked-in-ir-stage1=$checked_in_ir_stage1"
    echo "checked-in-ir-stage2=$checked_in_ir_stage2"
    echo "selfhost-source-present=$selfhost_source_present"
    echo "selfhost-ladder-present=$selfhost_ladder_present"
    echo "slice-ladder-present=$slice_ladder_present"
    echo "convergence-gate-present=$convergence_gate_present"
    echo "git-history-available=$git_history_available"
    echo "git-history-bootstrap-signal-count=$history_signal_count"
    echo "git-history-asset-signal-count=$history_asset_count"
    echo "candidate=A-historical-trusted-compiler-artifact"
    echo "candidate-A-status=$candidate_d_status"
    echo "candidate-A-non-circular=YES"
    echo "candidate-A-bounded=UNPROVEN"
    echo "candidate-A-auditable=PARTIAL_OR_OPAQUE"
    echo "candidate-A-can-produce-current-stage1=NOT_PROVEN"
    echo "candidate-A-reason=$candidate_d_reason"
    echo "candidate=B-frozen-bootstrap-semantic-snapshot"
    echo "candidate-B-status=$candidate_b_status"
    echo "candidate-B-non-circular=YES"
    echo "candidate-B-bounded=YES_IF_FROZEN"
    echo "candidate-B-auditable=YES_IF_MANIFESTED"
    echo "candidate-B-can-produce-current-stage1=NOT_PROVEN"
    echo "candidate-B-reason=$candidate_b_reason"
    echo "candidate=C-bootstrap-ladder"
    echo "candidate-C-status=$candidate_c_status"
    echo "candidate-C-non-circular=YES_IF_RUNG_ORDERED"
    echo "candidate-C-bounded=YES_IF_RUNGS_FROZEN"
    echo "candidate-C-auditable=YES_IF_EACH_RUNG_HAS_PROVENANCE"
    echo "candidate-C-can-produce-current-stage1=NOT_PROVEN"
    echo "candidate-C-reason=$candidate_c_reason"
    echo "candidate=D-historical-selfhost-source-root"
    echo "candidate-D-status=$candidate_a_status"
    echo "candidate-D-non-circular=YES"
    echo "candidate-D-bounded=PARTIAL"
    echo "candidate-D-auditable=YES"
    echo "candidate-D-can-produce-current-stage1=NOT_PROVEN"
    echo "candidate-D-reason=$candidate_a_reason"
    echo "history-top-signals-begin"
    sed 's/^/history=/' "$tmp/history.log" | head -30
    echo "history-top-signals-end"
    echo "history-asset-signals-begin"
    sed 's/^/history-asset=/' "$tmp/history-assets.log" | head -40
    echo "history-asset-signals-end"
    echo "best-candidate=$best_candidate"
    echo "recommended-next=$recommended_next"
    echo "final-trust-gate=Stage1_builds_Stage2_and_Stage2_builds_Stage3"
    echo "final-equivalence=Stage2_equiv_Stage3"
    echo "classification=$classification"
} | tee "$report"

if [ "$classification" = BOOTSTRAP_ROOT_NOT_SELECTED ]; then
    exit 1
fi
