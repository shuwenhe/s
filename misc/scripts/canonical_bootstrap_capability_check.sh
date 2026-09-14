#!/bin/sh
set -eu
root=${S_SOURCE_ROOT:-$(pwd)}
compiler=${1:?usage: canonical_bootstrap_capability_check.sh COMPILER CLOSURE OUTPUT_DIR}
closure=${2:?missing closure}
out=${3:?missing output directory}
test -x "$compiler"
test -s "$closure"
mkdir -p "$out"
work=$(mktemp -d "$out/canonical-capability.XXXXXX")
entry=$root/src/cmd/compile/modular_build_main.s
subset=$root/src/cmd/compile/stage0/bootstrap_subset.c
report=$work/report.txt
cp "$closure" "$work/closure.txt"
cp "$entry" "$work/canonical-entry.s"
cksum "$compiler" "$entry" "$subset" "$root/doc/bootstrap-subset.md" > "$work/checksums.txt"
# Compile the actual entry through ordinary build, without rewriting its package.
canonical_status=0
"$compiler" build "$entry" -o "$work/canonical-compiler" > "$work/canonical.log" 2>&1 || canonical_status=$?
main_status=0
cmd_status=0
main_exit=NOT_RUN
cmd_exit=NOT_RUN
for pkg in main cmd; do
    printf 'package %s\nfunc main() int { return 7 }\n' "$pkg" > "$work/$pkg.s"
    status=0
    "$compiler" build "$work/$pkg.s" -o "$work/$pkg" > "$work/$pkg.log" 2>&1 || status=$?
    if [ "$pkg" = main ]; then
        main_status=$status
        if [ "$status" -eq 0 ] && [ -x "$work/main" ]; then
            main_exit=0
            "$work/main" > "$work/main.run.log" 2>&1 || main_exit=$?
        fi
    else
        cmd_status=$status
        if [ "$status" -eq 0 ] && [ -x "$work/cmd" ]; then
            cmd_exit=0
            "$work/cmd" > "$work/cmd.run.log" 2>&1 || cmd_exit=$?
        fi
    fi
done
printf 'package cmd\nimport ()\nfunc main() int { return 7 }\n' > "$work/import.s"
import_status=0
import_exit=NOT_RUN
"$compiler" build "$work/import.s" -o "$work/import" > "$work/import.log" 2>&1 || import_status=$?
if [ "$import_status" -eq 0 ] && [ -x "$work/import" ]; then
    import_exit=0
    "$work/import" > "$work/import.run.log" 2>&1 || import_exit=$?
fi
{
    echo 'Phase 1.6 - Canonical Compiler Bootstrap Capability Audit'
    echo 'command=build'
    echo "entry=$entry"
    echo "evidence-directory=$work"
    echo "canonical-build-exit-status=$canonical_status"
    if [ -e "$work/canonical-compiler" ]; then
        echo 'canonical-output=PRESENT_NOT_AUTHORITY_PROOF'
    else
        echo 'canonical-output=ABSENT'
    fi
    sed 's/^/canonical-diagnostic=/' "$work/canonical.log"
    echo "package-main-control=build:$main_status exit:$main_exit"
    echo "package-cmd-control=build:$cmd_status exit:$cmd_exit"
    echo "import-declaration-control=build:$import_status exit:$import_exit"
    
    # Phase 1.6.1: named-package-declaration
    if [ "$main_status" -eq 0 ] && [ "$main_exit" = 7 ] &&
       [ "$cmd_status" -eq 0 ] && [ "$cmd_exit" = 7 ]; then
        echo 'named-package-declaration=PASS'
    else
        echo 'named-package-declaration=NOT_PROVEN'
    fi
    
    # Phase 1.6.2: import-declaration-structural-carry
    if [ "$import_status" -eq 0 ] && [ "$import_exit" = 7 ]; then
        echo 'import-declaration-structural-carry=PASS'
    else
        echo 'import-declaration-structural-carry=NOT_PROVEN'
    fi
    
    # Determine first-blocking-capability for canonical source
    if [ "$canonical_status" -ne 0 ] && [ "$cmd_status" -ne 0 ] &&
       [ "$main_status" -eq 0 ] && [ "$main_exit" = 7 ] &&
       [ ! -e "$work/canonical-compiler" ] && [ ! -e "$work/cmd" ] &&
       grep -qx 'package cmd' "$work/canonical-entry.s" &&
       grep -qx 'bootstrap-subset: byte 11: expected bootstrap keyword' "$work/canonical.log" &&
       grep -qx 'bootstrap-subset: byte 11: expected bootstrap keyword' "$work/cmd.log"; then
        echo 'first-blocking-capability=named-package-declaration'
        echo 'first-blocking-source=src/cmd/compile/modular_build_main.s:1'
        echo 'first-blocking-implementation=bootstrap_subset.c:bs_unit requires package main'
        echo 'result=BLOCKED'
        echo 'next-cut=single-unit-package-identifier-independent-of-main-function'
    elif [ "$canonical_status" -ne 0 ] && [ "$import_status" -ne 0 ] &&
       [ "$main_status" -eq 0 ] && [ "$main_exit" = 7 ] &&
       [ "$cmd_status" -eq 0 ] && [ "$cmd_exit" = 7 ] &&
       [ ! -e "$work/canonical-compiler" ] && [ ! -e "$work/import" ] &&
       grep -qx 'import (' "$work/canonical-entry.s"; then
        echo 'first-blocking-capability=import-declaration'
        echo 'first-blocking-source=src/cmd/compile/modular_build_main.s:2'
        echo 'first-blocking-implementation=bootstrap_subset.c:bs_unit expects func after package'
        echo 'result=BLOCKED'
        echo 'next-cut=import-declaration-representation-with-explicit-unresolved-dependencies'
    elif [ "$canonical_status" -ne 0 ] &&
         [ "$main_status" -eq 0 ] && [ "$main_exit" = 7 ] &&
         [ "$cmd_status" -eq 0 ] && [ "$cmd_exit" = 7 ] &&
         [ "$import_status" -eq 0 ] && [ "$import_exit" = 7 ] &&
         [ ! -e "$work/canonical-compiler" ]; then
        echo 'first-blocking-capability=canonical-source-compilation-beyond-phases-1-6-1-and-1-6-2'
        echo 'result=BLOCKED'
        echo 'note=phase-1-6-1-named-package-declaration-PASS'
        echo 'note=phase-1-6-2-import-declaration-structural-carry-PASS'
        echo 'next-cut=identify-next-blocker-in-canonical-source'
    else
        echo 'first-blocking-capability=NOT_LOCALIZED'
        echo 'result=REQUIRES_REVIEW'
        echo 'next-cut=inspect-fresh-canonical-and-control-diagnostics'
    fi
    echo 'later-gaps=STATIC_REQUIREMENTS_NOT_EXECUTED'
    echo 'capability-map=doc/canonical-bootstrap-capability.md'
    echo 'canonical-source-compilation=NOT_PROVEN'
    echo 'production-compiler-bootstrap=NOT_PROVEN'
    echo 'audit-exit-zero-means=report-produced-not-compilation-proven'
} > "$report"
cp "$report" "$out/canonical-bootstrap-capability-report.txt"
cat "$report"
