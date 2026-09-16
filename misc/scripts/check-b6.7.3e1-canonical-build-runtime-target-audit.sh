#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
entry_rel="src/cmd/compile/modular_build_main.s"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
stage0="${STAGE0_BIN:-"$root/.bootstrap/modular/s_stage0"}"
stage1="${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}"
stage1_c="${MODULAR_STAGE1_C:-"$stage1.c"}"
bootstrap_report="${MODULAR_BOOTSTRAP_REPORT:-"$root/.bootstrap/modular/bootstrap-report.txt"}"

tmp="${TMPDIR:-/tmp}/b6.7.3e1-runtime-target.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

if [ ! -x "$stage1" ]; then
    make -C "$root" modular-bootstrap >/dev/null
fi

closure_count=0
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
fi

closure_contains_entry=NO
if [ -f "$closure" ] && grep -qx "$entry_rel" "$closure"; then
    closure_contains_entry=YES
fi

current_producer=NONE
if [ -x "$stage0" ] && [ -f "$bootstrap_report" ] && grep -q "producer=$stage0" "$bootstrap_report"; then
    current_producer="$stage0"
fi

current_artifact=NONE
artifact_format=NONE
if [ -x "$stage1" ]; then
    current_artifact="$stage1"
    artifact_format="$(file "$stage1" | sed 's/.*: //')"
fi

contains_canonical_build_runtime=NO
contains_backend_elf64_build=NO
if [ -f "$stage1_c" ] && rg -q 'compile\.internal\.backend_elf64\.build|modular_build_main|canonical_build' "$stage1_c"; then
    contains_canonical_build_runtime=YES
fi
if [ -x "$stage1" ] && strings "$stage1" | rg -q 'compile\.internal\.backend_elf64|modular_build_main|canonical_build'; then
    contains_backend_elf64_build=YES
fi

stage0_can_produce_target=NO
if [ -x "$stage0" ] && [ -x "$stage1" ] && [ -f "$stage1_c" ]; then
    stage0_can_produce_target=ARTIFACT_STUB
fi

stage0_can_launch_target=NO
if [ -x "$stage1" ]; then
    set +e
    "$stage1" --help >"$tmp/stage1-help.log" 2>&1
    help_status=$?
    set -e
    if [ "$help_status" -eq 0 ]; then
        stage0_can_launch_target=ARTIFACT_STUB
    fi
fi

bootstrap_cycle=NO
if [ "$current_producer" = "$stage1" ]; then
    bootstrap_cycle=YES
fi

stage1_build_handler=UNKNOWN
if [ -f "$stage1_c" ] && rg -q 'return bootstrap_subset_build\(argv\[2\], argv\[4\]\)' "$stage1_c"; then
    stage1_build_handler=bootstrap_subset_build
fi
if [ -f "$stage1_c" ] && rg -q 'compile\.internal\.backend_elf64\.build|modular_build_main|canonical_build' "$stage1_c"; then
    stage1_build_handler=canonical_build
fi

set +e
bash "$root/misc/scripts/check-b6.7.3e-stage1-build-authority-handoff.sh" >"$tmp/3e.report" 2>&1
handoff_status=$?
set -e

missing_capability=NONE
classification=TARGET_EXISTS
if [ "$contains_canonical_build_runtime" != YES ] || [ "$contains_backend_elf64_build" != YES ]; then
    missing_capability=stage1-canonical-build-runtime-target
    classification=CANONICAL_RUNTIME_TARGET_MISSING
elif [ "$handoff_status" -ne 0 ]; then
    missing_capability=stage1-build-authority-handoff
    classification=TARGET_PARTIAL
fi

echo "B6.7.3e1 Canonical Build Runtime Target Audit"
echo "canonical-entry=$entry_rel"
echo "canonical-closure=$closure"
echo "canonical-closure-count=$closure_count"
echo "canonical-closure-contains-entry=$closure_contains_entry"
echo "current-producer=$current_producer"
echo "current-artifact=$current_artifact"
echo "artifact-format=$artifact_format"
echo "contains-canonical-build-runtime=$contains_canonical_build_runtime"
echo "contains-backend_elf64-build=$contains_backend_elf64_build"
echo "stage1-build-handler=$stage1_build_handler"
echo "stage0-can-produce-target=$stage0_can_produce_target"
echo "stage0-can-launch-target=$stage0_can_launch_target"
echo "bootstrap-cycle=$bootstrap_cycle"
echo "handoff-gate-status=$handoff_status"
if [ -s "$tmp/3e.report" ]; then
    sed 's/^/handoff-evidence=/' "$tmp/3e.report"
fi
echo "missing-capability=$missing_capability"
echo "classification=$classification"

if [ "$classification" != TARGET_EXISTS ]; then
    exit 1
fi
