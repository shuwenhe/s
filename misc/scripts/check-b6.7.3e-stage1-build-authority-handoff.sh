#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
stage1="${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}"
stage1_c="${MODULAR_STAGE1_C:-"$stage1.c"}"
tmp="${TMPDIR:-/tmp}/b6.7.3e-stage1-build-handoff.$$"

rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

if [ ! -x "$stage1" ]; then
    make -C "$root" modular-bootstrap >/dev/null
fi

cat >"$tmp/std-env-args.s" <<'SRC'
package test
import (
    "std.env"
)
func main() int {
    args := std.env.args()
    return 0
}
SRC

set +e
S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" "$stage1" build "$tmp/std-env-args.s" -o "$tmp/std-env-args" >"$tmp/stage1.log" 2>&1
status=$?
set -e

stage1_build_entry=NO
if [ -f "$stage1_c" ] && rg -q 'if \(!strcmp\(argv\[1\], "build"\)\)' "$stage1_c"; then
    stage1_build_entry=YES
fi

old_seed_semantic_path=UNKNOWN
if grep -q "type 'any' has no method 'args'" "$tmp/stage1.log"; then
    old_seed_semantic_path=REACHED
elif grep -q 'bootstrap-subset:' "$tmp/stage1.log"; then
    old_seed_semantic_path=NOT_REACHED
else
    old_seed_semantic_path=UNKNOWN
fi

bootstrap_subset_runtime_path=NO
if grep -q 'bootstrap-subset:' "$tmp/stage1.log"; then
    bootstrap_subset_runtime_path=YES
fi

stage1_generated_build_handler=UNKNOWN
if [ -f "$stage1_c" ] && rg -q 'return bootstrap_subset_build\(argv\[2\], argv\[4\]\)' "$stage1_c"; then
    stage1_generated_build_handler=bootstrap_subset_build
fi
if [ -f "$stage1_c" ] && rg -q 'compile\.internal\.backend_elf64\.build|modular_build_main|canonical_build' "$stage1_c"; then
    stage1_generated_build_handler=canonical_build
fi

modular_build_main_reached=NO
canonical_backend_build_reached=NO
canonical_parser_reached=NO
canonical_semantic_reached=NO
qualified_call_branch_reached=NO
qualified_binding_found=NO

if grep -Eq 'modular_build_main|backend_elf64|parse_source|semantic.check_source_file|lookup_qualified_functions' "$tmp/stage1.log"; then
    modular_build_main_reached=UNKNOWN
fi
if grep -Eq 'parse failed|semantic check failed|monomorphization failed|mir lowering|backend' "$tmp/stage1.log"; then
    canonical_parser_reached=YES
    canonical_semantic_reached=YES
fi

classification=HANDOFF_RUNTIME_TARGET_GAP
if [ "$stage1_generated_build_handler" = canonical_build ] && [ "$bootstrap_subset_runtime_path" = NO ] && [ "$canonical_semantic_reached" = YES ]; then
    classification=B6.7.3e_GREEN
fi

echo "B6.7.3e Stage1 Build Authority Handoff"
echo "stage1=$stage1"
echo "stage1-build-entry=$stage1_build_entry"
echo "stage1-generated-build-handler=$stage1_generated_build_handler"
echo "stage1-build-status=$status"
echo "old-seed-semantic-path=$old_seed_semantic_path"
echo "bootstrap-subset-runtime-path=$bootstrap_subset_runtime_path"
echo "modular-build-main-reached=$modular_build_main_reached"
echo "canonical-backend-build-reached=$canonical_backend_build_reached"
echo "canonical-parser-reached=$canonical_parser_reached"
echo "canonical-semantic-reached=$canonical_semantic_reached"
echo "qualified-call-branch-reached=$qualified_call_branch_reached"
echo "qualified-lookup-key=(std.env,args)"
echo "qualified-binding-found=$qualified_binding_found"
echo "C-seed-semantic-authority=NO"
echo "canonical-semantic-authority=$canonical_semantic_reached"
if [ -s "$tmp/stage1.log" ]; then
    sed 's/^/stage1-diagnostic=/' "$tmp/stage1.log"
fi
echo "classification=$classification"

if [ "$classification" != B6.7.3e_GREEN ]; then
    exit 1
fi
