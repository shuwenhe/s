#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
compiler="$root/bin/s_compiler"
source="$root/src/cmd/compile/pipeline/compiler_main.s"
report="$root/.bootstrap/bootstrap-authority/b1-canonical-build-dispatch.txt"
tmp_report="$report.tmp.$$"
work="${TMPDIR:-/tmp}/s-b1-canonical-build-dispatch.$$"

trap 'rm -rf "$work"; rm -f "$tmp_report"' EXIT HUP INT TERM
mkdir -p "$work" "$(dirname "$report")"

record() {
    result=$1
    reason=$2
    {
        echo "B1 canonical-build-dispatch"
        echo "compiler=$compiler"
        echo "source=$source"
        echo "fixture=$work/minimal.s"
        echo "artifact=$work/minimal"
        echo "canonical-build-entry=$canonical_build_entry"
        echo "bootstrap-subset-runtime-path=$bootstrap_subset_runtime_path"
        echo "seed-runtime-path=$seed_runtime_path"
        echo "old-binary-fallback=$old_binary_fallback"
        echo "build-exit-status=$build_status"
        echo "artifact-exists=$artifact_exists"
        echo "artifact-executable=$artifact_executable"
        echo "result=$result"
        echo "reason=$reason"
    } >"$tmp_report"
    mv "$tmp_report" "$report"
    cat "$report"
}

canonical_build_entry=NO
bootstrap_subset_runtime_path=NO
seed_runtime_path=NO
old_binary_fallback=NO
build_status=NOT_RUN
artifact_exists=NO
artifact_executable=NO

cat >"$work/minimal.s" <<'SRC'
package main

func main() int {
    return 42
}
SRC

if [ ! -x "$compiler" ]; then
    record FAIL "compiler not found or not executable"
    exit 1
fi

if grep -q 'import (.*compile.internal.backend_elf64' "$source" 2>/dev/null ||
   grep -q '"compile.internal.backend_elf64"' "$source" 2>/dev/null; then
    if grep -q 'args\[1\] == "build"' "$source" &&
       grep -q 'compile.internal.backend_elf64.build(args\[2\], args\[4\], "", false)' "$source"; then
        canonical_build_entry=YES
    fi
fi

set +e
"$compiler" build "$work/minimal.s" -o "$work/minimal" >"$work/build.log" 2>&1
status=$?
set -e
build_status=$status

if grep -Eq 'bootstrap-subset:' "$work/build.log"; then
    bootstrap_subset_runtime_path=YES
fi
if grep -Eq '(^|[^A-Za-z0-9_])(s_seed|bin/s_seed|src/cmd/compile/seed)([^A-Za-z0-9_]|$)' "$work/build.log"; then
    seed_runtime_path=YES
fi
if grep -Eiq 'fallback|old binary|old-binary|delegate|delegat' "$work/build.log"; then
    old_binary_fallback=YES
fi
if [ -f "$work/minimal" ] && [ -s "$work/minimal" ]; then
    artifact_exists=YES
fi
if [ -x "$work/minimal" ]; then
    artifact_executable=YES
fi

if [ "$canonical_build_entry" != YES ]; then
    record FAIL "missing canonical build dispatch to compile.internal.backend_elf64.build"
    exit 1
fi
if [ "$build_status" != 0 ]; then
    first_line=$(sed -n '1p' "$work/build.log" 2>/dev/null || true)
    record FAIL "build command failed: $first_line"
    exit 1
fi
if [ "$artifact_exists" != YES ] || [ "$artifact_executable" != YES ]; then
    record FAIL "build did not produce an executable artifact"
    exit 1
fi
if [ "$bootstrap_subset_runtime_path" != NO ] || [ "$seed_runtime_path" != NO ] || [ "$old_binary_fallback" != NO ]; then
    record FAIL "forbidden runtime authority marker observed"
    exit 1
fi

record PASS "B1 canonical build dispatch proven"
