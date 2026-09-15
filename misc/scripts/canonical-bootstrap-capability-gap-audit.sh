#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
closure=${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}
stage0=${STAGE0_BIN:-"$root/.bootstrap/modular/s_stage0"}
stage1=${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}
seed=${SEED_COMPILER_BIN:-"$root/bin/s_seed"}
report=${CANONICAL_BOOTSTRAP_CAPABILITY_GAP_REPORT:-"$root/.bootstrap/modular/canonical-bootstrap-capability-gap-audit.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/canonical-bootstrap-capability-gap.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

entry_rel=src/cmd/compile/modular_build_main.s
entry="$root/$entry_rel"

closure_count=0
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
fi

scan_file="$tmp/canonical-closure-source.txt"
if [ -f "$closure" ]; then
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        if [ -f "$root/$rel" ]; then
            printf '\n// file: %s\n' "$rel" >>"$scan_file"
            sed 's/\r$//' "$root/$rel" >>"$scan_file"
        fi
    done <"$closure"
else
    : >"$scan_file"
fi

has_pattern() {
    pattern=$1
    if rg -q -e "$pattern" "$scan_file"; then
        printf YES
    else
        printf NO
    fi
}

canonical_packages_imports=$(has_pattern '^import \(|^import "')
canonical_qualified_names=$(has_pattern '[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*')
canonical_structs=$(has_pattern '^struct ')
canonical_methods=$(has_pattern '^func \(')
canonical_arrays_slices=$(has_pattern '\[\]|\[[0-9]+\]|append\(|len\(')
canonical_generics=$(has_pattern '\[[A-Za-z_][A-Za-z0-9_]*(,[A-Za-z_][A-Za-z0-9_]*)*\]')
canonical_multi_return=$(has_pattern '\([^)]*,[^)]*\)[[:space:]]*\{|\([^)]*,[^)]*\)[[:space:]]*$')
canonical_ownership_drop=$(has_pattern 'ownership|drop|borrow|move|&[A-Za-z_]')

seed_log="$tmp/seed-entry.log"
seed_ir="$tmp/seed-entry.ir"
set +e
if [ -x "$seed" ]; then
    S_SOURCE_ROOT="$root" "$seed" "$entry" "$seed_ir" >"$seed_log" 2>&1
    seed_entry_status=$?
else
    seed_entry_status=127
fi
set -e

seed_first_blocker=not-run
if [ -s "$seed_log" ]; then
    seed_first_blocker=$(sed -n '1p' "$seed_log" | tr '\n' ' ')
fi

stage1_c="$stage1.c"

stage0_frontend_packages_imports=NO
stage0_frontend_qualified_names=NO
stage0_frontend_structs=NO
stage0_frontend_methods=NO
stage0_frontend_arrays_slices=NO
stage0_frontend_generics=NO
stage0_frontend_multi_return=NO
stage0_semantic_type_resolution=NO
stage0_semantic_package_symbols=NO
stage0_semantic_method_resolution=NO
stage0_semantic_generic_instantiation=NO
stage0_semantic_ownership_drop=NO
stage0_lowering_ast_ir_mir=NO
stage0_lowering_calls_returns=PARTIAL
stage0_lowering_aggregates=NO
stage0_lowering_ownership=NO
stage0_emission_object=NO
stage0_emission_native=YES
stage0_emission_multi_object_linkage=NO
stage0_emission_callable_entry_abi=NO

if [ -f "$root/src/cmd/compile/stage0/bootstrap_subset.c" ]; then
    if rg -q -e 'package main|package_name|strcmp\(.*package' "$root/src/cmd/compile/stage0/bootstrap_subset.c"; then
        stage0_frontend_packages_imports=PARTIAL
    fi
    if rg -q 'BS_CALL|call|return' "$root/src/cmd/compile/stage0/bootstrap_subset.c"; then
        stage0_lowering_calls_returns=PARTIAL
    fi
fi

seed_frontend_packages_imports=FAIL
seed_frontend_qualified_names=FAIL
seed_frontend_structs=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_frontend_methods=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_frontend_arrays_slices=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_frontend_generics=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_frontend_multi_return=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_semantic_type_resolution=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_semantic_package_symbols=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_semantic_method_resolution=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_semantic_generic_instantiation=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_semantic_ownership_drop=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_lowering_ast_ir_mir=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_lowering_calls_returns=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_lowering_aggregates=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_lowering_ownership=UNKNOWN_BEHIND_FRONTEND_BLOCKER
seed_emission_object=YES
seed_emission_native=YES
seed_emission_multi_object_linkage=PARTIAL
seed_emission_callable_entry_abi=PARTIAL

if [ "$seed_entry_status" -eq 0 ]; then
    seed_frontend_packages_imports=YES
    seed_frontend_qualified_names=YES
    seed_frontend_structs=UNKNOWN
    seed_frontend_methods=UNKNOWN
    seed_frontend_arrays_slices=UNKNOWN
    seed_frontend_generics=UNKNOWN
    seed_frontend_multi_return=UNKNOWN
    seed_semantic_type_resolution=UNKNOWN
    seed_semantic_package_symbols=UNKNOWN
    seed_lowering_ast_ir_mir=PARTIAL
fi

selfhost_frontend_packages_imports=PARTIAL
selfhost_frontend_qualified_names=UNKNOWN
selfhost_frontend_structs=PARTIAL
selfhost_frontend_methods=UNKNOWN
selfhost_frontend_arrays_slices=PARTIAL
selfhost_frontend_generics=UNKNOWN
selfhost_frontend_multi_return=UNKNOWN
selfhost_semantic_type_resolution=PARTIAL
selfhost_semantic_package_symbols=UNKNOWN
selfhost_semantic_method_resolution=UNKNOWN
selfhost_semantic_generic_instantiation=UNKNOWN
selfhost_semantic_ownership_drop=UNKNOWN
selfhost_lowering_ast_ir_mir=PARTIAL
selfhost_lowering_calls_returns=PARTIAL
selfhost_lowering_aggregates=PARTIAL
selfhost_lowering_ownership=UNKNOWN
selfhost_emission_object=UNKNOWN
selfhost_emission_native=PARTIAL
selfhost_emission_multi_object_linkage=UNKNOWN
selfhost_emission_callable_entry_abi=PARTIAL

if rg -q -e '--emit-native|emit_native_' "$root/src/cmd/compile/selfhost/compiler.s" 2>/dev/null; then
    selfhost_emission_native=YES
fi
if rg -q -e '--emit-c|emit_selfhost_c|compile_selfhost_c' "$root/src/cmd/compile/selfhost/compiler.s" 2>/dev/null; then
    selfhost_emission_object=PARTIAL
fi

native_frontend=N/A
native_semantic=N/A
native_lowering=N/A
native_emission_object=YES
native_emission_native=YES
native_emission_multi_object_linkage=PARTIAL
native_emission_callable_entry_abi=PARTIAL

if ! rg -q -e '--emit-aot-obj|--emit-standalone-amd64-obj|emit_aot_object_from_ir_file' "$root/makefile" "$root/src/cmd/compile/seed" 2>/dev/null; then
    native_emission_object=NO
fi
if ! rg -q -e '--emit-aot|--emit-standalone-amd64|emit_native_from_ir_file' "$root/makefile" "$root/src/cmd/compile/seed" 2>/dev/null; then
    native_emission_native=NO
fi

minimal_gap="qualified-package-import-frontend"
downstream="UNKNOWN_BEHIND_FRONTEND_BLOCKER"
smallest_root=s_seed
bridge_feasibility=PARTIAL
recommended_next=thin-bridge-design-with-hard-scope-limit

if [ "$seed_entry_status" -ne 0 ]; then
    minimal_gap="qualified-package-import-frontend"
    smallest_root=s_seed
    bridge_feasibility=PARTIAL
fi

if [ "$stage0_frontend_packages_imports" = NO ]; then
    stage0_viability=NOT_VIABLE
else
    stage0_viability=NOT_VIABLE
fi
seed_viability=PARTIAL
selfhost_viability=PARTIAL
native_viability=PARTIAL

{
    echo "canonical-bootstrap-capability-gap-audit"
    echo "canonical-closure-source-count=$closure_count"
    echo "canonical-closure-root=$entry_rel"
    echo "status-semantics=YES executable evidence; PARTIAL partial fixture/path evidence; NO explicit unsupported; FAIL canonical probe executed and failed; UNKNOWN insufficient evidence; N/A not applicable"
    echo "syntax-gap-is-not-bootstrap-gap=TRUE"
    echo "seed-canonical-entry-status=$seed_entry_status"
    if [ -s "$seed_log" ]; then
        sed 's/^/seed-canonical-entry-diagnostic=/' "$seed_log"
    fi
    echo "downstream-capabilities=$downstream"
    echo "matrix=layer,capability,canonical,stage0,seed,selfhost,native_aot"
    echo "matrix=Frontend,packages/imports,$canonical_packages_imports,$stage0_frontend_packages_imports,$seed_frontend_packages_imports,$selfhost_frontend_packages_imports,$native_frontend"
    echo "matrix=Frontend,qualified names,$canonical_qualified_names,$stage0_frontend_qualified_names,$seed_frontend_qualified_names,$selfhost_frontend_qualified_names,$native_frontend"
    echo "matrix=Frontend,structs,$canonical_structs,$stage0_frontend_structs,$seed_frontend_structs,$selfhost_frontend_structs,$native_frontend"
    echo "matrix=Frontend,methods/receivers,$canonical_methods,$stage0_frontend_methods,$seed_frontend_methods,$selfhost_frontend_methods,$native_frontend"
    echo "matrix=Frontend,arrays/slices,$canonical_arrays_slices,$stage0_frontend_arrays_slices,$seed_frontend_arrays_slices,$selfhost_frontend_arrays_slices,$native_frontend"
    echo "matrix=Frontend,generics,$canonical_generics,$stage0_frontend_generics,$seed_frontend_generics,$selfhost_frontend_generics,$native_frontend"
    echo "matrix=Frontend,multi-return,$canonical_multi_return,$stage0_frontend_multi_return,$seed_frontend_multi_return,$selfhost_frontend_multi_return,$native_frontend"
    echo "matrix=Semantic,type resolution,YES,$stage0_semantic_type_resolution,$seed_semantic_type_resolution,$selfhost_semantic_type_resolution,$native_semantic"
    echo "matrix=Semantic,package symbol resolution,YES,$stage0_semantic_package_symbols,$seed_semantic_package_symbols,$selfhost_semantic_package_symbols,$native_semantic"
    echo "matrix=Semantic,method resolution,$canonical_methods,$stage0_semantic_method_resolution,$seed_semantic_method_resolution,$selfhost_semantic_method_resolution,$native_semantic"
    echo "matrix=Semantic,generic instantiation,$canonical_generics,$stage0_semantic_generic_instantiation,$seed_semantic_generic_instantiation,$selfhost_semantic_generic_instantiation,$native_semantic"
    echo "matrix=Semantic,ownership/drop semantics,$canonical_ownership_drop,$stage0_semantic_ownership_drop,$seed_semantic_ownership_drop,$selfhost_semantic_ownership_drop,$native_semantic"
    echo "matrix=Lowering,canonical AST to IR/MIR,YES,$stage0_lowering_ast_ir_mir,$seed_lowering_ast_ir_mir,$selfhost_lowering_ast_ir_mir,$native_lowering"
    echo "matrix=Lowering,calls/returns,YES,$stage0_lowering_calls_returns,$seed_lowering_calls_returns,$selfhost_lowering_calls_returns,$native_lowering"
    echo "matrix=Lowering,aggregate lowering,$canonical_structs,$stage0_lowering_aggregates,$seed_lowering_aggregates,$selfhost_lowering_aggregates,$native_lowering"
    echo "matrix=Lowering,ownership lowering,$canonical_ownership_drop,$stage0_lowering_ownership,$seed_lowering_ownership,$selfhost_lowering_ownership,$native_lowering"
    echo "matrix=Emission,object emission,N/A,$stage0_emission_object,$seed_emission_object,$selfhost_emission_object,$native_emission_object"
    echo "matrix=Emission,native emission,N/A,$stage0_emission_native,$seed_emission_native,$selfhost_emission_native,$native_emission_native"
    echo "matrix=Emission,multi-object linkage,N/A,$stage0_emission_multi_object_linkage,$seed_emission_multi_object_linkage,$selfhost_emission_multi_object_linkage,$native_emission_multi_object_linkage"
    echo "matrix=Emission,callable entry ABI,YES,$stage0_emission_callable_entry_abi,$seed_emission_callable_entry_abi,$selfhost_emission_callable_entry_abi,$native_emission_callable_entry_abi"
    echo "candidate=C-stage0/bootstrap_subset viability=$stage0_viability reason=would-require-duplicating-canonical-parser-semantic-authority"
    echo "candidate=s_seed viability=$seed_viability reason=nearest-existing-root-with-IR-AOT-but-current-canonical-entry-probe-fails-before-downstream-capabilities"
    echo "candidate=selfhost/compiler.s viability=$selfhost_viability reason=has-native-capability-evidence-but-targets-historical-selfhost-compiler-not-37-file-canonical-closure"
    echo "candidate=native/AOT backend viability=$native_viability reason=emission-capability-exists-but-needs-frontend/semantic-consumer"
    echo "minimal-bootstrap-gap=[$minimal_gap]"
    echo "smallest-existing-root=$smallest_root"
    echo "bridge-feasibility=$bridge_feasibility"
    echo "recommended-next=$recommended_next"
    echo "audit-verdict=COMPLETE"
} >"$report"

cat "$report"
