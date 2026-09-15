#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
stage1=${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}
stage1_c=${MODULAR_STAGE1_C:-"$stage1.c"}
report=${STAGE1_CANONICAL_BUILD_DISPATCH_REPORT:-"$root/.bootstrap/modular/stage1-canonical-build-dispatch-report.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/stage1-canonical-build-dispatch.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

generic_src="$tmp/generic_probe.s"
generic_out="$tmp/generic_probe"
generic_log="$tmp/generic.log"

cat >"$generic_src" <<'SRC'
package main

func identity[T](T x) T {
    return x
}

func main() int {
    x := identity[int](42)
    return x
}
SRC

stage1_build_handler=UNKNOWN
if [ -f "$stage1_c" ] && rg -q 'return bootstrap_subset_build\(argv\[2\], argv\[4\]\)' "$stage1_c"; then
    stage1_build_handler=bootstrap_subset
fi
if [ -f "$stage1_c" ] && rg -q 'compile\.internal\.backend_elf64\.build|modular_build_main|canonical_build' "$stage1_c"; then
    stage1_build_handler=canonical
fi

canonical_build_entry=NO
if [ -f "$stage1_c" ] && rg -q 'compile\.internal\.backend_elf64\.build|modular_build_main|canonical_build' "$stage1_c"; then
    canonical_build_entry=YES
fi

set +e
S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" "$stage1" build "$generic_src" -o "$generic_out" >"$generic_log" 2>&1
generic_status=$?
set -e

bootstrap_subset_runtime_path=NO
if grep -q 'bootstrap-subset:' "$generic_log"; then
    bootstrap_subset_runtime_path=YES
fi

generic_parser_reached=UNKNOWN
if [ "$bootstrap_subset_runtime_path" = YES ]; then
    generic_parser_reached=NO
elif grep -Eq 'parse failed:|syntax|parser|semantic|monomorphization|mir lowering|backend' "$generic_log"; then
    generic_parser_reached=YES
fi

semantic_reached=UNKNOWN
if grep -Eq 'semantic|monomorphization|mir lowering|backend' "$generic_log"; then
    semantic_reached=YES
fi

mono_reached=UNKNOWN
if grep -Eq 'monomorphization|mir lowering|backend' "$generic_log"; then
    mono_reached=YES
fi

missing_capability=NONE
stage1_build_authority=CANONICAL
if [ "$canonical_build_entry" != YES ]; then
    missing_capability=stage1-canonical-entry-linkage
    stage1_build_authority=NOT_TRANSFERRED
elif [ "$bootstrap_subset_runtime_path" != NO ]; then
    missing_capability=production-build-still-delegates-to-bootstrap-subset
    stage1_build_authority=NOT_TRANSFERRED
elif [ "$generic_parser_reached" != YES ]; then
    missing_capability=generic-parser-reachability-not-proven
    stage1_build_authority=NOT_TRANSFERRED
fi

{
    echo "stage1-canonical-build-dispatch-check"
    echo "stage1-entry=$stage1"
    echo "stage1-generated-c=$stage1_c"
    echo "stage1-build-handler=$stage1_build_handler"
    echo "canonical-build-entry=$canonical_build_entry"
    echo "bootstrap-subset-runtime-path=$bootstrap_subset_runtime_path"
    echo "generic-build-status=$generic_status"
    echo "generic-parser-reached=$generic_parser_reached"
    echo "semantic-reached=$semantic_reached"
    echo "mono-reached=$mono_reached"
    echo "missing-capability=$missing_capability"
    if [ -s "$generic_log" ]; then
        sed 's/^/generic-diagnostic=/' "$generic_log"
    fi
    echo "stage1-build-authority=$stage1_build_authority"
} >"$report"

cat "$report"

if [ "$stage1_build_authority" != CANONICAL ]; then
    exit 1
fi
