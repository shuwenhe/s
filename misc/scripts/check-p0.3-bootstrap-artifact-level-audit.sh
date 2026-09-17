#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
entry_rel="src/cmd/compile/modular_build_main.s"
report="${P03_BOOTSTRAP_ARTIFACT_LEVEL_REPORT:-"$root/.bootstrap/modular/p0.3-bootstrap-artifact-level-audit.txt"}"

canonical_bootstrap_ir="${CANONICAL_STAGE1_BOOTSTRAP_IR:-"$root/src/cmd/compile/bootstrap/bootstrap.ir"}"
canonical_bootstrap_ir_manifest="${CANONICAL_STAGE1_BOOTSTRAP_MANIFEST:-"$root/src/cmd/compile/bootstrap/bootstrap.manifest"}"
canonical_mir_artifact="${CANONICAL_STAGE1_BOOTSTRAP_MIR:-"$root/src/cmd/compile/bootstrap/stage1.mir"}"
canonical_lowered_ir_artifact="${CANONICAL_STAGE1_LOWERED_IR:-"$root/src/cmd/compile/bootstrap/stage1.lowered"}"
canonical_c_artifact="${CANONICAL_STAGE1_GENERATED_C:-"$root/src/cmd/compile/bootstrap/stage1.c"}"
canonical_object_artifact="${CANONICAL_STAGE1_OBJECT:-"$root/src/cmd/compile/bootstrap/stage1.o"}"
canonical_native_artifact="${CANONICAL_STAGE1_NATIVE:-"$root/src/cmd/compile/bootstrap/stage1"}"

legacy_compiler_ir="$root/.bootstrap/compiler/compiler.ir"
legacy_selfhost_stage1_ir="$root/.bootstrap/selfhost/stage1.ir"
legacy_selfhost_stage1="$root/.bootstrap/selfhost/stage1"
legacy_selfhost_stage2="$root/.bootstrap/selfhost/stage2"
legacy_selfhost_manifest="$root/.bootstrap/selfhost/manifest.txt"

mkdir -p "$(dirname "$report")"

bool_file() {
    [ -f "$1" ] && echo YES || echo NO
}

bool_exec() {
    [ -x "$1" ] && echo YES || echo NO
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

sha_file() {
    if [ -f "$1" ]; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo NONE
    fi
}

closure_count=0
canonical_snapshot=NOT_FOUND
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if [ "$closure_count" -gt 0 ] && grep -qx "$entry_rel" "$closure"; then
        canonical_snapshot=FOUND
    fi
fi

seed_aot_consumer=$(status_bool has_text 'emit_aot_from_ir_file|emit_native_from_ir_file|--emit-aot' src/cmd/compile/seed)
host_cc_available=NO
if command -v cc >/dev/null 2>&1; then
    host_cc_available=YES
fi
object_linker_available=NO
if command -v ld >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; then
    object_linker_available=YES
fi
os_loader_available=YES

stage2_regeneration_script=NO
if [ -x "$root/misc/scripts/check-stage1-canonical-build-authority.sh" ] || \
   has_text 'stage2|stage3|cmp' makefile src/cmd/dist misc/scripts; then
    stage2_regeneration_script=PARTIAL
fi

p02_report="$root/.bootstrap/modular/p0.2-executor-compatibility-audit.txt"
p02_historical_verdict=UNKNOWN
if [ -f "$p02_report" ]; then
    p02_historical_verdict=$(awk -F= '$1 == "historical-root-verdict" { print $2 }' "$p02_report" | tail -n 1)
    [ -n "$p02_historical_verdict" ] || p02_historical_verdict=UNKNOWN
fi

legacy_selfhost_stage1_file=NONE
if [ -f "$legacy_selfhost_stage1" ]; then
    legacy_selfhost_stage1_file=$(file "$legacy_selfhost_stage1" 2>/dev/null || echo UNKNOWN)
fi

legacy_selfhost_ir_verdict=REFERENCE_ONLY
if [ -f "$legacy_selfhost_stage1_ir" ] && \
   rg -q 'build_main|host_args' "$legacy_selfhost_stage1_ir" 2>/dev/null && \
   ! rg -q 'modular_build_main|backend_elf64|check_source_file|parse_source' "$legacy_selfhost_stage1_ir" 2>/dev/null; then
    legacy_selfhost_ir_verdict=REFERENCE_ONLY_HISTORICAL_SELFHOST_NOT_CANONICAL_MODULAR
fi

legacy_native_verdict=REFERENCE_ONLY
if [ -x "$legacy_selfhost_stage1" ]; then
    legacy_native_verdict=REFERENCE_ONLY_HISTORICAL_EXECUTOR_NOT_CURRENT_CANONICAL
fi

canonical_bootstrap_ir_exists=$(bool_file "$canonical_bootstrap_ir")
canonical_bootstrap_ir_manifest_exists=$(bool_file "$canonical_bootstrap_ir_manifest")
canonical_bootstrap_ir_hash=$(sha_file "$canonical_bootstrap_ir")

canonical_mir_exists=$(bool_file "$canonical_mir_artifact")
canonical_lowered_ir_exists=$(bool_file "$canonical_lowered_ir_artifact")
canonical_c_exists=$(bool_file "$canonical_c_artifact")
canonical_object_exists=$(bool_file "$canonical_object_artifact")
canonical_native_exists=$(bool_file "$canonical_native_artifact")
canonical_native_executable=$(bool_exec "$canonical_native_artifact")

sseed_can_produce_stage1=NO
if [ "$canonical_bootstrap_ir_exists" = YES ] && [ "$seed_aot_consumer" = YES ]; then
    sseed_can_produce_stage1=YES
fi

c_can_produce_stage1=NO
if [ "$canonical_c_exists" = YES ] && [ "$host_cc_available" = YES ]; then
    c_can_produce_stage1=YES
fi

object_can_produce_stage1=NO
if [ "$canonical_object_exists" = YES ] && [ "$object_linker_available" = YES ]; then
    object_can_produce_stage1=YES
fi

native_can_produce_stage1=NO
if [ "$canonical_native_executable" = YES ]; then
    native_can_produce_stage1=YES
fi

selected_level=NONE
minimum_trusted_bootstrap_surface=NONE
gate=RED

if [ "$native_can_produce_stage1" = YES ]; then
    selected_level=LEVEL5_NATIVE_EXECUTABLE
    minimum_trusted_bootstrap_surface='OS loader + checked canonical Stage1 executable artifact'
    gate=YELLOW
elif [ "$object_can_produce_stage1" = YES ]; then
    selected_level=LEVEL5_OBJECT
    minimum_trusted_bootstrap_surface='host linker + checked canonical object artifact'
    gate=YELLOW
elif [ "$sseed_can_produce_stage1" = YES ]; then
    selected_level=LEVEL4_SSEED_IR
    minimum_trusted_bootstrap_surface='seed AOT consumer + checked canonical SSEED IR artifact'
    gate=YELLOW
elif [ "$c_can_produce_stage1" = YES ]; then
    selected_level=LEVEL4_GENERATED_C
    minimum_trusted_bootstrap_surface='host C compiler + checked canonical generated C artifact'
    gate=YELLOW
fi

{
    echo "P0.3 BOOTSTRAP_ARTIFACT_LEVEL_AUDIT"
    echo "P0_3_BOOTSTRAP_ARTIFACT_LEVEL_AUDIT=$gate"
    echo
    echo "canonical-snapshot=$canonical_snapshot"
    echo "canonical-snapshot-path=$closure"
    echo "canonical-snapshot-count=$closure_count"
    echo
    echo "executor-contract:"
    echo "  allowed=read frozen artifact; verify version/hash; execute encoded operations; produce Stage1"
    echo "  forbidden=S Parser; S Semantic Analysis; Generic resolution; Method resolution; Ownership/Borrow/NLL; Drop semantics"
    echo "  anti-goal=s_seed_v2"
    echo
    echo "consumers:"
    echo "  SSEED_IR_TO_AOT=$seed_aot_consumer"
    echo "  GENERATED_C_TO_HOST_CC=$host_cc_available"
    echo "  OBJECT_TO_EXECUTABLE=$object_linker_available"
    echo "  NATIVE_EXECUTABLE_TO_STAGE1=$os_loader_available"
    echo
    echo "artifact-levels:"
    echo "  level1-source:"
    echo "    artifact-exists=$canonical_snapshot"
    echo "    executor-complexity=FULL_COMPILER"
    echo "    requires-s-semantics=YES"
    echo "    verdict=REJECT_AS_BOOTSTRAP_ROOT"
    echo
    echo "  level2-canonical-ast-or-typed-ast:"
    echo "    artifact-exists=NO"
    echo "    executor-complexity=HIGH"
    echo "    requires-s-semantics=YES"
    echo "    verdict=NO_ARTIFACT_AND_TOO_HIGH_LEVEL"
    echo
    echo "  level3-canonical-mir:"
    echo "    artifact-exists=$canonical_mir_exists"
    echo "    executor-complexity=MEDIUM"
    echo "    requires-s-semantics=NO_PARSER_SEMANTIC_MONO_ALREADY_CROSSED"
    echo "    can-produce-stage1=NO"
    echo "    verdict=INTERESTING_BUT_NO_ARTIFACT_OR_EXECUTOR"
    echo
    echo "  level4-lowered-ir:"
    echo "    artifact-exists=$canonical_lowered_ir_exists"
    echo "    executor-complexity=LOW_TO_MEDIUM"
    echo "    requires-s-semantics=NO"
    echo "    can-produce-stage1=NO"
    echo "    verdict=NO_ARTIFACT"
    echo
    echo "  level4-sseed-ir:"
    echo "    artifact-exists=$canonical_bootstrap_ir_exists"
    echo "    manifest-exists=$canonical_bootstrap_ir_manifest_exists"
    echo "    artifact-hash=$canonical_bootstrap_ir_hash"
    echo "    executor-complexity=LOW"
    echo "    requires-s-semantics=NO"
    echo "    target-dependent=PARTIAL"
    echo "    can-produce-stage1=$sseed_can_produce_stage1"
    echo "    verdict=CONSUMER_EXISTS_ARTIFACT_MISSING"
    echo
    echo "  level4-generated-c:"
    echo "    artifact-exists=$canonical_c_exists"
    echo "    executor-complexity=LOW_EXTERNAL_HOST_CC"
    echo "    requires-s-semantics=NO"
    echo "    target-dependent=PARTIAL"
    echo "    can-produce-stage1=$c_can_produce_stage1"
    echo "    verdict=CONSUMER_AVAILABLE_ARTIFACT_MISSING"
    echo
    echo "  level5-object:"
    echo "    artifact-exists=$canonical_object_exists"
    echo "    executor-complexity=LOW_EXTERNAL_LINKER"
    echo "    requires-s-semantics=NO"
    echo "    target-dependent=YES"
    echo "    can-produce-stage1=$object_can_produce_stage1"
    echo "    verdict=NO_CANONICAL_OBJECT_ARTIFACT"
    echo
    echo "  level5-native-executable:"
    echo "    artifact-exists=$canonical_native_exists"
    echo "    executable=$canonical_native_executable"
    echo "    executor-complexity=MINIMAL_OS_LOADER"
    echo "    requires-s-semantics=NO"
    echo "    target-dependent=YES"
    echo "    can-produce-stage1=$native_can_produce_stage1"
    echo "    verdict=NO_CANONICAL_NATIVE_ARTIFACT"
    echo
    echo "legacy-reference-artifacts:"
    echo "  .bootstrap/compiler/compiler.ir-exists=$(bool_file "$legacy_compiler_ir")"
    echo "  .bootstrap/selfhost/stage1.ir-exists=$(bool_file "$legacy_selfhost_stage1_ir")"
    echo "  .bootstrap/selfhost/stage1.ir-verdict=$legacy_selfhost_ir_verdict"
    echo "  .bootstrap/selfhost/stage1-exists=$(bool_file "$legacy_selfhost_stage1")"
    echo "  .bootstrap/selfhost/stage1-executable=$(bool_exec "$legacy_selfhost_stage1")"
    echo "  .bootstrap/selfhost/stage1-file=$legacy_selfhost_stage1_file"
    echo "  .bootstrap/selfhost/stage1-verdict=$legacy_native_verdict"
    echo "  .bootstrap/selfhost/stage2-exists=$(bool_file "$legacy_selfhost_stage2")"
    echo "  .bootstrap/selfhost/manifest-exists=$(bool_file "$legacy_selfhost_manifest")"
    echo "  p0.2-historical-root-verdict=$p02_historical_verdict"
    echo
    echo "regeneration:"
    echo "  Stage1->Stage2=NOT_PROVEN"
    echo "  Stage2->Stage3=NOT_PROVEN"
    echo "  Stage2/Stage3-equivalence=NOT_PROVEN"
    echo "  regeneration-script=$stage2_regeneration_script"
    echo
    echo "selected-level=$selected_level"
    echo "minimum-trusted-bootstrap-surface=$minimum_trusted_bootstrap_surface"
    echo
    echo "ROOT_BLOCKER=NO_CHECKED_CANONICAL_STAGE1_ARTIFACT_AT_ANY_EXECUTABLE_LEVEL"
    echo "NEED_NEW_BOUNDED_TRUSTED_EXECUTOR=YES"
    echo "SOURCE_PURITY_AS_BOOTSTRAP_ROOT=REJECTED"
    echo "MIR_TO_SSEED_ADAPTER=NOT_FIRST_BLOCKER"
    echo "DIRECT_SEED_CLOSURE=REJECTED"
    echo "HISTORICAL_ROOT_AS_PRIMARY_EXECUTOR=REJECTED"
} | tee "$report"

[ "$gate" = GREEN ]
