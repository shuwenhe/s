#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
tmp="${TMPDIR:-/tmp}/stage1-canonical-build-authority.$$"
report="${STAGE1_CANONICAL_BUILD_AUTHORITY_REPORT:-"$root/.bootstrap/modular/stage1-canonical-build-authority-report.txt"}"

rm -rf "$tmp"
mkdir -p "$tmp" "$(dirname "$report")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

stage1_ir="$tmp/modular_build_main.ir"
stage1="$tmp/s_modular-stage1"
closure="$tmp/stage1-build-closure.txt"
fixture="$tmp/return42.s"
fixture_out="$tmp/return42"
seed_compile_log="$tmp/seed-compile.log"
emit_log="$tmp/emit-aot.log"
stage1_build_log="$tmp/stage1-build.log"
fixture_run_log="$tmp/fixture-run.log"

cat >"$fixture" <<'SRC'
package main

func main() int {
    return 42
}
SRC

grep -v '^src/cmd/compile/internal/tests/' "$root/.bootstrap/modular/canonical-closure.txt" >"$closure"

set +e
"$root/bin/s_seed" --compile-unit "$stage1_ir" $(sed 's#^#'"$root"'/#' "$closure") >"$seed_compile_log" 2>&1
seed_status=$?
if [ "$seed_status" -eq 0 ]; then
    S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-aot "$stage1_ir" "$stage1" >"$emit_log" 2>&1
    emit_status=$?
else
    emit_status=127
fi
if [ "$emit_status" -eq 0 ]; then
    S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" "$stage1" build "$fixture" -o "$fixture_out" >"$stage1_build_log" 2>&1
    stage1_build_status=$?
else
    stage1_build_status=127
fi
if [ -x "$fixture_out" ]; then
    "$fixture_out" >"$fixture_run_log" 2>&1
    fixture_exit=$?
else
    fixture_exit=127
fi
set -e

bootstrap_subset_runtime_path=NO
if grep -q 'bootstrap-subset:' "$stage1_build_log" "$fixture_run_log" 2>/dev/null; then
    bootstrap_subset_runtime_path=YES
fi

unknown_module_arg=NO
if grep -Eq 'unknown arg value: (std|compile|internal)\.' "$stage1_build_log" "$fixture_run_log" 2>/dev/null; then
    unknown_module_arg=YES
fi

seed_first_error=NONE
if [ -s "$seed_compile_log" ]; then
    seed_first_error=$(grep -E '^(PARSE_FAIL|error\[)' "$seed_compile_log" | head -1 || true)
    if [ -z "$seed_first_error" ]; then
        seed_first_error=$(sed -n '1p' "$seed_compile_log")
    fi
fi

canonical_chain_static=NO
if rg -q 'return compile\.internal\.backend_elf64\.build\(args\[2\], args\[4\], "", false\)' "$root/src/cmd/compile/modular_build_main.s" &&
   rg -q 'compile\.internal\.syntax\.parse_source\(source\)' "$root/src/cmd/compile/internal/backend_elf64.s" &&
   rg -q 'compile\.internal\.semantic\.check_source_file\(combined, source\)' "$root/src/cmd/compile/internal/backend_elf64.s" &&
   rg -q 'compile\.internal\.mono\.monomorphize_file\(combined\)' "$root/src/cmd/compile/internal/backend_elf64.s" &&
   rg -q 'compile\.internal\.ir\.lower\.lower_main_to_mir\(parsed\)' "$root/src/cmd/compile/internal/backend_elf64.s"; then
    canonical_chain_static=YES
fi

authority=NOT_PROVEN
if [ "$seed_status" -eq 0 ] &&
   [ "$emit_status" -eq 0 ] &&
   [ "$stage1_build_status" -eq 0 ] &&
   [ "$fixture_exit" -eq 42 ] &&
   [ "$bootstrap_subset_runtime_path" = NO ] &&
   [ "$unknown_module_arg" = NO ] &&
   [ "$canonical_chain_static" = YES ]; then
    authority=PROVEN
fi

{
    echo "stage1-canonical-build-authority"
    echo "seed-source-to-ir-status=$seed_status"
    echo "seed-ir-to-stage1-status=$emit_status"
    echo "stage1-build-return42-status=$stage1_build_status"
    echo "return42-exit=$fixture_exit"
    echo "seed-first-error=$seed_first_error"
    echo "bootstrap-subset-runtime-path=$bootstrap_subset_runtime_path"
    echo "unknown-module-arg=$unknown_module_arg"
    echo "canonical-chain-static=$canonical_chain_static"
    echo "path-evidence=stage1 build -> modular_build_main.build -> compile.internal.backend_elf64.build -> syntax.parse_source -> semantic.check_source_file -> mono -> MIR -> backend"
    if [ -s "$seed_compile_log" ]; then sed 's/^/seed-compile=/' "$seed_compile_log"; fi
    if [ -s "$emit_log" ]; then sed 's/^/emit-aot=/' "$emit_log"; fi
    if [ -s "$stage1_build_log" ]; then sed 's/^/stage1-build=/' "$stage1_build_log"; fi
    if [ -s "$fixture_run_log" ]; then sed 's/^/return42-run=/' "$fixture_run_log"; fi
    echo "STAGE1_CANONICAL_BUILD_AUTHORITY=$authority"
} >"$report"

cat "$report"

if [ "$authority" != PROVEN ]; then
    exit 1
fi
