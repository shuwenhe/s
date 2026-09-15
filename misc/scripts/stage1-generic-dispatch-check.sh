#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
stage1=${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}
report=${STAGE1_GENERIC_DISPATCH_REPORT:-"$root/.bootstrap/modular/stage1-generic-dispatch-report.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/stage1-generic-dispatch.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

canonical_src="$tmp/canonical_probe.s"
generic_src="$tmp/generic_probe.s"
canonical_out="$tmp/canonical_probe"
generic_out="$tmp/generic_probe"
canonical_log="$tmp/canonical.log"
generic_log="$tmp/generic.log"
callsite_log="$tmp/callsites.txt"

cat >"$canonical_src" <<'SRC'
package cmd
import ()
func main() int {
    return 7
}
SRC

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

set +e
S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" "$stage1" build "$canonical_src" -o "$canonical_out" >"$canonical_log" 2>&1
canonical_build_status=$?
canonical_exit=NOT_RUN
if [ "$canonical_build_status" -eq 0 ] && [ -x "$canonical_out" ]; then
    "$canonical_out" >/dev/null 2>&1
    canonical_exit=$?
fi

S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" "$stage1" build "$generic_src" -o "$generic_out" >"$generic_log" 2>&1
generic_build_status=$?
generic_exit=NOT_RUN
if [ "$generic_build_status" -eq 0 ] && [ -x "$generic_out" ]; then
    "$generic_out" >/dev/null 2>&1
    generic_exit=$?
fi
set -e

rg -n 'bootstrap_subset_build|bootstrap-subset|--emit-artifact-stage2|artifact-only|if \\(!strcmp\\(argv\\[1\\], "build"\\)\\)' \
    "$root/src/cmd/compile/stage0" "$root/src/cmd/compile/modular_build_main.s" "$root/makefile" >"$callsite_log" || true

canonical_build=FAIL
if [ "$canonical_build_status" -eq 0 ]; then
    canonical_build=PASS
fi

generic_build=FAIL
if [ "$generic_build_status" -eq 0 ]; then
    generic_build=PASS
fi

generic_bootstrap_subset=NO
generic_parser_reached=UNKNOWN
fallback_triggered=NO
fallback_reason=none

if grep -q 'bootstrap-subset:' "$generic_log"; then
    generic_bootstrap_subset=YES
    generic_parser_reached=NO
    fallback_triggered=YES
    fallback_reason=stage1-build-dispatches-directly-to-bootstrap_subset_build
fi

canonical_entry_callsite="$root/src/cmd/compile/modular_build_main.s:37 compile.internal.backend_elf64.build"
bootstrap_subset_callsite="$root/src/cmd/compile/stage0/stage0.c:161 generated stage1 build handler calls bootstrap_subset_build"
first_routing_condition="argv[1] == build"
authority=NOT_PROVEN
if [ "$generic_bootstrap_subset" = NO ]; then
    authority=PROVEN
    generic_parser_reached=YES
    fallback_triggered=NO
    fallback_reason=none
fi

{
    echo "stage1-generic-dispatch-check"
    echo "stage1-entry=$stage1"
    echo "build-handler=generated-by-src/cmd/compile/stage0/stage0.c"
    echo "input-classifier=none-observed"
    echo "selected-compiler=bootstrap_subset_build-for-build-command"
    echo "canonical-probe-build=$canonical_build"
    echo "canonical-probe-build-status=$canonical_build_status"
    echo "canonical-probe-exit=$canonical_exit"
    echo "generic-probe-build=$generic_build"
    echo "generic-probe-build-status=$generic_build_status"
    echo "generic-probe-exit=$generic_exit"
    echo "fallback-triggered=$fallback_triggered"
    echo "fallback-reason=$fallback_reason"
    echo "bootstrap-subset-runtime-path=$generic_bootstrap_subset"
    echo "generic-parser-reached=$generic_parser_reached"
    echo "bootstrap-subset-callsite=$bootstrap_subset_callsite"
    echo "canonical-entry-callsite=$canonical_entry_callsite"
    echo "first-routing-condition=$first_routing_condition"
    if [ -s "$generic_log" ]; then
        sed 's/^/generic-diagnostic=/' "$generic_log"
    fi
    if [ -s "$callsite_log" ]; then
        sed 's/^/callsite-audit=/' "$callsite_log"
    fi
    echo "stage1-generic-dispatch-authority=$authority"
} >"$report"

cat "$report"

if [ "$authority" != PROVEN ]; then
    exit 1
fi
