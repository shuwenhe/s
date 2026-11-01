#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
report=${CANONICAL_THIN_BOOTSTRAP_BRIDGE_DESIGN_REPORT:-"$root/.bootstrap/modular/canonical-thin-bootstrap-bridge-design-report.txt"}

mkdir -p "$(dirname -- "$report")"

forbidden_violation=NO

{
    echo "canonical-thin-bootstrap-bridge-design-check"
    echo "purpose=define-thin-bridge-boundaries-not-implementation"
    echo "bridge-source-authority=NONE"
    echo "bridge-semantic-authority=NONE"
    echo "bridge-mono-authority=NONE"
    echo "bridge-ownership-authority=NONE"
    echo "bridge-mir-authority=NONE"
    echo "bridge-backend-authority=NONE"
    echo "bootstrap-subset-expansion=FORBIDDEN"
    echo "syntax-gap-is-not-bootstrap-gap=TRUE"
    echo "pass-does-not-mean-bridge-exists=TRUE"
    echo "pass-does-not-mean-stage1-authority-transferred=TRUE"
    echo "allowed=canonical-closure-discovery-ordering"
    echo "allowed=package-import-path-mapping"
    echo "allowed=qualified-name-transport-normalization"
    echo "allowed=canonical-source-to-existing-seed-consumable-representation"
    echo "allowed=existing-ir-aot-invocation"
    echo "allowed=object-native-artifact-collection"
    echo "allowed=stage1-linkage"
    echo "allowed=canonical-entry-abi-exposure"
    echo "allowed-transform=lexical-source-rewriting-with-equivalence-proof"
    echo "allowed-emission=existing-seed-ir-aot-only"
    echo "forbidden=new-parser-authority"
    echo "forbidden=new-semantic-typecheck-authority"
    echo "forbidden=new-generic-mono-authority"
    echo "forbidden=new-ownership-drop-authority"
    echo "forbidden=new-mir-authority"
    echo "forbidden=new-optimization-authority"
    echo "forbidden=new-backend-codegen-authority"
    echo "forbidden=bootstrap-subset-as-second-compiler"
    echo "scope-escalation-policy=STOP_ON_SEMANTIC_GAP"
    echo "scope-escalation-policy=STOP_ON_GENERIC_MONO_GAP"
    echo "scope-escalation-policy=STOP_ON_OWNERSHIP_DROP_GAP"
    echo "scope-escalation-policy=STOP_ON_MIR_LOWERING_GAP"
    echo "scope-escalation-policy=STOP_ON_BACKEND_CODEGEN_GAP"
    echo "gap-class=TRANSPORT_GAP action=bridge-may-continue-with-equivalence-proof"
    echo "gap-class=EXISTING_SEED_CAPABILITY action=reuse-existing-root-path"
    echo "gap-class=SEMANTIC_GAP action=abort-thin-bridge-and-recommend-bootstrap-root-redesign"
    echo "gap-class=LOWERING_GAP action=abort-thin-bridge-and-reassess-root"
    echo "gap-class=BACKEND_GAP action=reuse-existing-aot-only-bridge-must-not-implement-backend"
    echo "progressive-probe=P0 canonical-entry-syntax"
    echo "progressive-probe=P1 qualified-package-import"
    echo "progressive-probe=P2 first-imported-canonical-module"
    echo "progressive-probe=P3 transitive-imports"
    echo "progressive-probe=P4 full-37-file-closure"
    echo "first-probe-target=qualified-package-import-frontend"
    echo "first-probe-success=parser-progresses-beyond-current-compile.internal.semantic-blocker"
    echo "first-probe-non-goal=full-37-file-closure-pass"
    echo "first-probe-non-goal=generic-native-e2e"
    echo "decision-rule=if-bridge-requires-forbidden-capability-then-bridge-feasibility-NOT_VIABLE"
    echo "decision-rule=if-downstream-capability-hidden-behind-fronted-blocker-then-report-UNKNOWN_BEHIND_FRONTEND_BLOCKER"
    echo "next-if-transport-gap=B2.3-first-transport-probe"
    echo "next-if-semantic-gap=bootstrap-root-redesign"
    echo "forbidden-violation=$forbidden_violation"
    echo "bridge-design=BOUNDED"
} >"$report"

cat "$report"

if [ "$forbidden_violation" != NO ]; then
    exit 1
fi
