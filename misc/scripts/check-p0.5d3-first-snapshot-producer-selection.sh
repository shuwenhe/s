#!/usr/bin/env bash
set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
manifest="$root/.bootstrap/modular/canonical-closure.freeze.manifest"
report="${P05D3_REPORT:-$root/.bootstrap/modular/p0.5d3-first-snapshot-producer-selection.txt}"
expected=17df24ba79f4d818a994d66608f8deb61848ae54ebda339c1204f11f22fcd8f2
commit=6e066805d55ce190bdf816f79953e36713220f7a
tmp=$(mktemp -d "${TMPDIR:-/tmp}/s-p05d3.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cd "$root"

# Verify the frozen input without invoking the manifest-writing freeze gate.
fail() {
    printf '%s\n' 'P0_5D_3_FIRST_SNAPSHOT_PRODUCER_SELECTION=REJECT' \
        "FIRST_UNRESOLVED_PRODUCER_REQUIREMENT=$1" 'snapshot-generation=BLOCKED' >"$tmp/report"
    mkdir -p "$(dirname "$report")"
    cp "$tmp/report" "$report"
    cat "$report"
    exit 2
}
test -f "$manifest" || fail MISSING_FROZEN_MANIFEST
for field in 'closure.version=1' 'closure.hash-algorithm=sha256' \
    'closure.file-count=37' "closure.git-commit=$commit" \
    "closure.aggregate-sha256=$expected"; do
    test "$(grep -Fxc "$field" "$manifest" || true)" = 1 || fail INVALID_FROZEN_MANIFEST
done
awk '/^\[ordered-file-list\]$/ { active=1; next } /^\[/ { active=0 } active && /^file=/ { sub(/^file=/, ""); print }' "$manifest" >"$tmp/files"
awk '/^\[per-file-sha256\]$/ { active=1; next } /^\[/ { active=0 } active && NF { print }' "$manifest" >"$tmp/frozen"
test "$(wc -l <"$tmp/files" | tr -d ' ')" = 37 || fail INVALID_FILE_COUNT
test "$(sort -u "$tmp/files" | wc -l | tr -d ' ')" = 37 || fail DUPLICATE_INPUT
: >"$tmp/current"
: >"$tmp/commit"
while IFS= read -r rel; do
    case "$rel" in src/*.s) ;; *) fail INVALID_SOURCE_PATH ;; esac
    case "$rel" in *..*|*\\*) fail INVALID_SOURCE_PATH ;; esac
    test -f "$rel" || fail MISSING_SOURCE
    digest=$(shasum -a 256 "$rel" | awk '{print $1}')
    printf '%s  %s\n' "$digest" "$rel" >>"$tmp/current"
    git show "$commit:$rel" >"$tmp/blob" || fail MISSING_COMMIT_SOURCE
    digest=$(shasum -a 256 "$tmp/blob" | awk '{print $1}')
    printf '%s  %s\n' "$digest" "$rel" >>"$tmp/commit"
done <"$tmp/files"
cmp -s "$tmp/current" "$tmp/frozen" || fail SOURCE_BINDING_MISMATCH
cmp -s "$tmp/commit" "$tmp/frozen" || fail COMMIT_BINDING_MISMATCH
test "$(shasum -a 256 "$tmp/current" | awk '{print $1}')" = "$expected" || fail AGGREGATE_MISMATCH

evidence=(
    doc/p0.5d3-first-snapshot-producer-selection.md
    src/cmd/compile/compiler.s
    src/cmd/compile/internal/backend_elf64.s
    .bootstrap/modular/b6.7.3e2c-generated-c-producer-audit.txt
    .bootstrap/modular/p0.1-canonical-artifact-producer-feasibility.txt
    .bootstrap/modular/p0.2-executor-compatibility-audit.txt
)
for path in "${evidence[@]}"; do
    test -f "$path" || fail MISSING_AUDIT_EVIDENCE
done
{
    printf '%s\n' 'P0_5D_3_FIRST_SNAPSHOT_PRODUCER_SELECTION=PARTIAL' \
        'MODE=AUDIT_DESIGN_ONLY' "canonical-source-hash=$expected" \
        "canonical-source-commit=$commit" 'canonical-source-file-count=37' \
        'source-binding=MATCH' 'selected-producer=NONE' 'selected-producer-class=NONE' \
        'producer-input=canonical-closure.freeze.manifest' 'producer-output=SSEED-TARGET-V1' \
        'semantic-responsibility=FIXED_CLOSURE_TRANSLATION_REQUIRES_EXPLICIT_REVIEW' \
        'one-time-semantic-trust=REQUIRED_NOT_DISCHARGED' 'trust-lifetime=ONE_TIME_REQUIRED' \
        'long-term-semantic-authority=NO' 'requires-seed-semantic-expansion=NO' \
        'requires-third-long-term-compiler=NO' 'reproducibility=DEFINED_NOT_PROVEN' \
        'independent-verification=REQUIRED_NOT_PROVEN' \
        'provenance-contract=doc/p0.5d3-first-snapshot-producer-selection.md' \
        'candidate-A=REJECT:CURRENT_INPUT_AND_OUTPUT_PATH_INSUFFICIENT' \
        'candidate-B=REJECT:CURRENT_CLOSURE_EXECUTION_UNPROVEN_PRIOR_PROBE_FAILED' \
        'candidate-C=PARTIAL:NO_CONCRETE_BOUNDED_REFERENCE_PROCESS' \
        'candidate-D=PARTIAL:NO_REVIEWED_FULL_CLOSURE_TRANSLATION_PLAN' \
        'candidate-E=PARTIAL:VERIFICATION_STRATEGY_REQUIRES_ELIGIBLE_PRODUCERS' \
        'candidate-F=PARTIAL:NO_PROVEN_EXECUTOR_OR_COMPLETE_SSEED_EMITTER' \
        'FIRST_UNRESOLVED_PRODUCER_REQUIREMENT=CONCRETE_BOUNDED_PRODUCER_WITH_FULL_CLOSURE_COVERAGE_AND_INDEPENDENT_REVIEW' \
        'snapshot-generation=BLOCKED' 'snapshot-acceptance=BLOCKED' \
        'compiler-probes-run=NO' 'historical-evidence=SUPPORTING_NOT_EXACT_CLOSURE_EXECUTION_PROOF' \
        'auto-selection=DISABLED_REQUIRES_REVIEWED_EVIDENCE' '[evidence-sha256]'
    shasum -a 256 "$manifest" "${evidence[@]}"
} >"$tmp/report"
mkdir -p "$(dirname "$report")"
cp "$tmp/report" "$report"
cat "$report"
# PARTIAL is an expected blocking result, never a successful selection.
exit 1
