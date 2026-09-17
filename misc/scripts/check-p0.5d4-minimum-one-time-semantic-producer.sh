#!/usr/bin/env bash
set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
report="${P05D4_REPORT:-$root/.bootstrap/modular/p0.5d4-minimum-one-time-semantic-producer.txt}"
spec=doc/p0.5d4-minimum-one-time-semantic-producer.md
expected=17df24ba79f4d818a994d66608f8deb61848ae54ebda339c1204f11f22fcd8f2
tmp=$(mktemp -d "${TMPDIR:-/tmp}/s-p05d4.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cd "$root"

publish() {
    mkdir -p "$(dirname "$report")"
    cp "$tmp/report" "$report"
    cat "$report"
}
fail() {
    printf '%s\n' 'P0_5D_4_MINIMUM_ONE_TIME_SEMANTIC_PRODUCER=RED' \
        "FIRST_UNRESOLVED_REQUIREMENT=$1" 'minimum-producer-contract=INCOMPLETE' \
        'snapshot-generation=BLOCKED' >"$tmp/report"
    publish
    exit 2
}

# Reuse the read-only closure/commit verifier. PARTIAL is expected, not success.
check=misc/scripts/check-p0.5d3-first-snapshot-producer-selection.sh
test -f "$check" || fail MISSING_SOURCE_BINDING_CHECK
prior_rc=0
S_ROOT="$root" P05D3_REPORT="$tmp/source-binding" bash "$check" >"$tmp/prior.log" 2>&1 || prior_rc=$?
test "$prior_rc" = 1 && test -f "$tmp/source-binding" || fail SOURCE_OR_PRIOR_EVIDENCE_INVALID
grep -qx 'source-binding=MATCH' "$tmp/source-binding" || fail SOURCE_BINDING_NOT_MATCHED
grep -qx "canonical-source-hash=$expected" "$tmp/source-binding" || fail UNEXPECTED_SOURCE_HASH
test -f "$spec" || fail MISSING_SPECIFICATION

evidence=(
    src/cmd/compile/modular_build_main.s
    src/cmd/compile/internal/syntax/syntax.s
    src/cmd/compile/internal/semantic.s
    src/cmd/compile/internal/mono/monomorphization.s
    src/cmd/compile/internal/ir/lower.s
    src/cmd/compile/internal/mir.s
    src/cmd/compile/internal/backend_elf64.s
    src/cmd/compile/internal/abi/abiutils.s
    src/env/env.s
    src/cmd/compile/seed/code/generator.c
    src/cmd/compile/seed/code/backend_registry.c
    src/cmd/compile/seed/code/native_backend.c
)
for path in "${evidence[@]}"; do
    test -f "$path" || fail MISSING_EVIDENCE
done

# This is a reviewed design verdict, not semantic proof inferred by grep.
{
    printf '%s\n' 'P0_5D_4_MINIMUM_ONE_TIME_SEMANTIC_PRODUCER=YELLOW' \
        'MODE=AUDIT_DESIGN_ONLY' "canonical-source-hash=$expected" \
        'source-binding=MATCH' 'canonical-file-count=37' \
        'producer-input-contract=DEFINED' 'producer-output-contract=SSEED-TARGET-V1' \
        'required-semantic-transformations=T01_PARSE,T02_BIND_AND_TYPE,T03_MONO,T04_OWNERSHIP_CLEANUP,T05_FULL_CFG,T06_LAYOUT_ABI_RUNTIME,T07_INTERPRETER_BEHAVIOR,T08_ENCODING' \
        'semantic-end=NOT_PROVEN' 'post-semantic-encoding=NOT_PROVEN' \
        'post-semantic-encoding-required=MECHANICAL_ONLY' \
        'observed-mir=SELECTED_FUNCTION_WITH_SOURCE_TEXT' \
        'observed-backend=SOURCE_INTERPRETATION_WITH_MIR_FALLBACK_THEN_WRITES_EXIT_EMISSION' \
        'target-runtime-profile=NOT_FROZEN' 'regeneration-route=NOT_PROVEN' \
        'producer-lifetime=ONE_TIME' 'long-term-semantic-authority=FORBIDDEN' \
        'producer-required-after-convergence=NO' 'independent-review-contract=DEFINED' \
        'independent-review-completed=NO' 'convergence-contract=Stage1->Stage2->Stage3;Stage2==Stage3' \
        'convergence-proves-initial-translation=NO' 'minimum-producer-contract=INCOMPLETE' \
        'FIRST_UNRESOLVED_REQUIREMENT=FULL_CLOSURE_EXECUTABLE_SEMANTIC_BOUNDARY_NOT_PROVEN' \
        'producer-selection-round-two=BLOCKED' 'snapshot-generation=BLOCKED' \
        'snapshot-acceptance=BLOCKED' 'compiler-execution=NOT_RUN' \
        "specification=$spec" '[evidence-sha256]'
    shasum -a 256 .bootstrap/modular/canonical-closure.freeze.manifest "$spec" "$check" "${evidence[@]}"
} >"$tmp/report"
publish
exit 1
