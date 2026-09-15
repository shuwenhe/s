#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
closure=${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}
stage0=${STAGE0_BIN:-"$root/.bootstrap/modular/s_stage0"}
stage1=${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}
seed=${SEED_COMPILER_BIN:-"$root/bin/s_seed"}
report=${STAGE1_BOOTSTRAP_MECHANISM_REPORT:-"$root/.bootstrap/modular/stage1-bootstrap-mechanism-audit.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/stage1-bootstrap-mechanism.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

entry_rel=src/cmd/compile/modular_build_main.s
entry="$root/$entry_rel"
stage1_c="$stage1.c"

canonical_closure_source_count=0
if [ -f "$closure" ]; then
    canonical_closure_source_count=$(wc -l <"$closure" | tr -d ' ')
fi

stage0_compiler_capability=UNKNOWN
if [ -f "$root/src/cmd/compile/stage0/stage0.c" ] && \
   rg -q 'bootstrap_subset_build|bootstrap_subset\.c' "$root/src/cmd/compile/stage0/stage0.c"; then
    stage0_compiler_capability=BOOTSTRAP_SUBSET
fi

stage0_can_compile_canonical_closure=NO
if [ -f "$stage1_c" ] && rg -q 'compile\.internal\.backend_elf64|modular_build_main|canonical_build' "$stage1_c"; then
    stage0_can_compile_canonical_closure=YES
fi

existing_seed_compiler=NO
if [ -x "$seed" ]; then
    existing_seed_compiler=YES
fi

seed_log="$tmp/seed-canonical-entry.log"
seed_ir="$tmp/modular_build_main.ir"
existing_seed_can_compile_canonical_closure=NO
set +e
if [ -x "$seed" ]; then
    S_SOURCE_ROOT="$root" "$seed" "$entry" "$seed_ir" >"$seed_log" 2>&1
    seed_status=$?
else
    seed_status=127
fi
set -e
if [ "${seed_status:-127}" -eq 0 ] && [ -s "$seed_ir" ]; then
    existing_seed_can_compile_canonical_closure=SINGLE_ENTRY_ONLY
fi

existing_s_to_c_path=NO
if rg -q -e '--emit-c|compile_selfhost_c|emit_selfhost_c' "$root/makefile" "$root/src/cmd/compile/selfhost" 2>/dev/null; then
    existing_s_to_c_path=PARTIAL_SELFHOST
fi

existing_s_to_object_path=NO
if rg -q -e '--emit-aot-obj|--emit-standalone-amd64-obj|emit_aot_object_from_ir_file|emit_standalone_amd64_object_from_ir_file' \
    "$root/makefile" "$root/src/cmd/compile/seed" 2>/dev/null; then
    existing_s_to_object_path=SEED_IR_AOT
fi

existing_s_to_native_path=NO
if rg -q -e '--emit-aot|--emit-standalone-amd64|--emit-native|emit_native_from_ir_file' \
    "$root/makefile" "$root/src/cmd/compile/seed" "$root/src/cmd/compile/selfhost" 2>/dev/null; then
    existing_s_to_native_path=YES
fi

existing_stage1_object_link_path=NO
if rg -q -e 'cc .*s_modular-stage1.*canonical.*\\.o|ld .*s_modular-stage1.*canonical.*\\.o|canonical-closure.*\\.o' \
    "$root/makefile" "$root/src/cmd/compile/stage0" 2>/dev/null; then
    existing_stage1_object_link_path=YES
fi

existing_canonical_entry_abi=NO
if rg -q '^func main\(\) int' "$entry"; then
    existing_canonical_entry_abi=CLI_MAIN_SOURCE
fi

class_stage0=NOT_VIABLE
reason_stage0=would-require-expanding-bootstrap_subset-into-duplicate-compiler-authority
if [ "$stage0_can_compile_canonical_closure" = YES ]; then
    class_stage0=VIABLE
    reason_stage0=stage0-generated-stage1-contains-canonical-entry
fi

class_seed=NOT_VIABLE
reason_seed=cannot-prove-full-canonical-closure-consumption-without-seed-semantic-authority
if [ "$existing_seed_can_compile_canonical_closure" = SINGLE_ENTRY_ONLY ]; then
    class_seed=PARTIAL
    reason_seed=can-emit-ir-for-entry-file-but-not-proven-as-non-circular-canonical-closure-consumer
fi

class_modular=NOT_VIABLE
reason_modular=stage1-requires-stage1-until-canonical-entry-linkage-exists
if [ -x "$stage1" ] && [ "$stage0_can_compile_canonical_closure" = YES ]; then
    class_modular=VIABLE
    reason_modular=stage1-has-canonical-entry
fi

class_aot=PARTIAL
reason_aot=object-native-emission-exists-for-seed-ir-selfhost-paths-but-no-stage1-canonical-closure-link-integration
if [ "$existing_s_to_object_path" = NO ] && [ "$existing_s_to_native_path" = NO ]; then
    class_aot=NOT_VIABLE
    reason_aot=no-object-or-native-emission-path-found
fi

class_historical=PARTIAL
reason_historical=selfhost-slice-artifacts-target-src-cmd-compile-selfhost-compiler-s-not-canonical-modular-closure
if ! rg -q 'selfhost|slice|native-codegen' "$root/makefile" "$root/misc/scripts" 2>/dev/null; then
    class_historical=NOT_VIABLE
    reason_historical=no-historical-selfhost-artifacts-found
fi

bootstrap_mechanism=MISSING
first_missing_capability=stage1-canonical-closure-consumption
recommended_consumption_path=design-non-circular-bootstrap-root-for-canonical-closure-consumption
if [ "$existing_stage1_object_link_path" = YES ] && [ "$existing_canonical_entry_abi" != NO ]; then
    bootstrap_mechanism=PARTIAL_OBJECT_LINK
    first_missing_capability=stage1-canonical-entry-callability
    recommended_consumption_path=wire-existing-object-link-path-to-canonical-entry
fi

{
    echo "stage1-bootstrap-mechanism-audit"
    echo "canonical-closure-source-count=$canonical_closure_source_count"
    echo "canonical-closure-root=$entry_rel"
    echo "stage0-current-compiler=$stage0"
    echo "stage0-compiler-capability=$stage0_compiler_capability"
    echo "stage0-can-compile-canonical-closure=$stage0_can_compile_canonical_closure"
    echo "existing-seed-compiler=$existing_seed_compiler"
    echo "existing-seed-can-compile-canonical-closure=$existing_seed_can_compile_canonical_closure"
    echo "seed-canonical-entry-status=${seed_status:-127}"
    if [ -s "$seed_log" ]; then
        sed 's/^/seed-canonical-entry-diagnostic=/' "$seed_log"
    fi
    echo "existing-s-to-c-path=$existing_s_to_c_path"
    echo "existing-s-to-object-path=$existing_s_to_object_path"
    echo "existing-s-to-native-path=$existing_s_to_native_path"
    echo "existing-stage1-object-link-path=$existing_stage1_object_link_path"
    echo "existing-canonical-entry-abi=$existing_canonical_entry_abi"
    echo "candidate=C-stage0-bootstrap_subset class=$class_stage0 reason=$reason_stage0"
    echo "candidate=s_seed class=$class_seed reason=$reason_seed"
    echo "candidate=modular-compiler class=$class_modular reason=$reason_modular"
    echo "candidate=native-aot-backend class=$class_aot reason=$reason_aot"
    echo "candidate=historical-selfhost-artifacts class=$class_historical reason=$reason_historical"
    echo "bootstrap-mechanism=$bootstrap_mechanism"
    echo "first-missing-capability=$first_missing_capability"
    echo "recommended-consumption-path=$recommended_consumption_path"
    echo "verdict=BOOTSTRAP_MECHANISM_NOT_PROVEN"
} >"$report"

cat "$report"

exit 1
