#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${CANONICAL_BOOTSTRAP_ROOT_STRATEGY_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-root-strategy-design-report.txt"}

mkdir -p "$(dirname -- "$report")"

seed_ir_aot=NO
if rg -q -e '--emit-aot|--emit-aot-obj|--emit-standalone-amd64|--emit-bin' "$root/makefile" "$root/src/cmd/compile/seed" 2>/dev/null; then
    seed_ir_aot=YES
fi

selfhost_emit_c=NO
if rg -q -e '--emit-c|emit_selfhost_c|compile_selfhost_c' "$root/src/cmd/compile/selfhost/compiler.s" "$root/makefile" 2>/dev/null; then
    selfhost_emit_c=YES
fi

convergence_evidence=NO
if rg -q 'stage2.*stage3|Stage2.*Stage3|bootstrap-convergence|cmp .*stage2.*stage3' "$root/makefile" "$root/src/cmd/compile" "$root/misc/scripts" 2>/dev/null; then
    convergence_evidence=YES
fi

preferred_root_artifact=IR
fallback_root_artifact=C
preferred_reason=existing-seed-ir-aot-is-the-smallest-current-artifact-consumer-and-avoids-host-c-abi-as-primary-bootstrap-surface
if [ "$seed_ir_aot" != YES ]; then
    preferred_root_artifact=C
    fallback_root_artifact=IR
    preferred_reason=seed-ir-aot-consumer-not-found-so-generated-c-is-the-more-reviewable-bootstrap-artifact
fi

forbidden_violation=NO

{
    echo "canonical-bootstrap-root-strategy-design-check"
    echo "purpose=design-only-no-artifact-generation"
    echo "root-kind=GENERATED_ARTIFACT"
    echo "root-artifact=$preferred_root_artifact"
    echo "preferred-root-artifact=$preferred_root_artifact"
    echo "fallback-root-artifact=$fallback_root_artifact"
    echo "preferred-reason=$preferred_reason"
    echo "root-purpose=BOOTSTRAP_ONLY"
    echo "root-semantic-authority=BOUNDED_SNAPSHOT"
    echo "root-authority-scope=STAGE1_CREATION_ONLY"
    echo "root-runtime-authority-after-stage1=NONE"
    echo "root-artifact-source=GENERATED_FROM_CANONICAL_COMPILER"
    echo "hand-maintained-bootstrap-semantics=FORBIDDEN"
    echo "manual-semantic-patching=FORBIDDEN"
    echo "bootstrap-subset-expansion=FORBIDDEN"
    echo "long-term-dual-semantic-authority=FORBIDDEN"
    echo "bootstrap-input=CHECKED_IN_ROOT_ARTIFACT"
    echo "bootstrap-input-role=TRUST_ANCHOR"
    echo "bootstrap-edge=checked-in-root-artifact -> existing-artifact-consumer -> canonical-stage1"
    echo "bootstrap-circularity=FORBIDDEN"
    echo "regeneration-input=CANONICAL_STAGE2_OR_STAGE3"
    echo "regeneration-edge=canonical-stage2-or-stage3 -> regenerated-root-artifact -> normalized-equivalence-check"
    echo "regeneration-before-stage1=FORBIDDEN"
    echo "artifact-consumer=existing-seed-ir-aot"
    echo "artifact-consumer-evidence=$seed_ir_aot"
    echo "artifact-regenerator=canonical-compiler"
    echo "artifact-regenerator-evidence=REQUIRED_IN_B3_3_OR_LATER"
    echo "stage1-generation=bootstrap-root-only"
    echo "authority-handoff=after-stage1-created"
    echo "stage1-build-authority=CANONICAL"
    echo "stage2-build-authority=CANONICAL"
    echo "stage3-build-authority=CANONICAL"
    echo "bootstrap-root-runtime-authority-after-stage1=NONE"
    echo "equivalence=E1-semantic-equivalence REQUIRED"
    echo "equivalence=E2-stage1-behavior-equivalence REQUIRED"
    echo "equivalence=E3-deterministic-ir-or-c-artifact-after-normalization REQUIRED"
    echo "equivalence=E4-byte-identical-native-artifact DESIRABLE_PLATFORM_DEPENDENT"
    echo "equivalence-proof=checked-in-root-stage1-behavior-equals-regenerated-root-stage1-behavior"
    echo "convergence-proof=stage2-stage3-semantic-and-artifact-convergence"
    echo "existing-evidence=seed-ir-aot-consumer $seed_ir_aot"
    echo "existing-evidence=selfhost-emit-c $selfhost_emit_c"
    echo "existing-evidence=stage2-stage3-convergence-pattern $convergence_evidence"
    echo "ir-risk=ir-format-stability-and-canonical-closure-expressiveness-not-yet-proven"
    echo "c-risk=host-c-compiler-c-abi-and-generated-c-correctness-expand-trust-surface"
    echo "ir-selection-rule=if-ir-cannot-enter-aot-without-seed-semantic-expansion-then-switch-to-c-or-redesign-root"
    echo "c-selection-rule=if-c-requires-hand-maintained-semantics-then-root-strategy-invalid"
    echo "mandatory-final-gate=canonical-selfhost-convergence-check"
    echo "final-gate-requires=stage1-produced-by-bootstrap-root"
    echo "final-gate-requires=stage2-produced-by-canonical-stage1"
    echo "final-gate-requires=stage3-produced-by-canonical-stage2"
    echo "final-gate-requires=stage2-stage3-semantic-equivalence=YES"
    echo "final-gate-requires=stage2-stage3-artifact-convergence=YES"
    echo "final-gate-requires=bootstrap-root-used-after-stage1=NO"
    echo "next=B3.3-root-artifact-feasibility-probe"
    echo "non-goal=generate-bootstrap-artifact-now"
    echo "non-goal=fix-std-undeclared"
    echo "non-goal=stage1-build-authority-handoff"
    echo "forbidden-violation=$forbidden_violation"
    echo "root-strategy=BOUNDED"
} >"$report"

cat "$report"

if [ "$forbidden_violation" != NO ]; then
    exit 1
fi
