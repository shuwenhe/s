#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
compiler=${1:?usage: parser_execution_path_check.sh COMPILER REPORT}
report=${2:?usage: parser_execution_path_check.sh COMPILER REPORT}
stage0=$root/src/cmd/compile/stage0/stage0.c
negative=$root/src/cmd/compile/internal/tests/fixtures/parser_authority_reject.s
closure=$root/.bootstrap/modular/canonical-closure.txt
canonical_frontend=src/cmd/compile/internal/syntax/syntax.s
canonical_parser=src/s/parser.s

tmp="${report}.tmp.$$"
trap 'rm -f "$tmp.reject"' EXIT HUP INT TERM

reject_status=0
"$compiler" check "$negative" >"$tmp.reject" 2>&1 || reject_status=$?

check_branch=$(grep -n 'strcmp(argv\[1\], "check")\|strcmp(argv\[1\],\\"check\\")' "$stage0" | head -n 1 || true)
generated_stub=$(grep -n 'free(read_file(argv\[2\])).*return 0' "$stage0" | head -n 1 || true)
stage2_stub=$(grep -n 'strcmp(argv\[1\],\\"check\\").*return 0' "$stage0" | head -n 1 || true)

{
    echo "Phase 2.1b Canonical Parser Wiring Probe"
    echo "========================================"
    echo "command=check"
    echo "compiler=$compiler"
    echo "negative-fixture=src/cmd/compile/internal/tests/fixtures/parser_authority_reject.s"
    echo "exit-status=$reject_status"
    if grep -qxF "$canonical_frontend" "$closure" 2>/dev/null &&
       grep -qxF "$canonical_parser" "$closure" 2>/dev/null; then
        echo "canonical-parser-source-present=YES"
        echo "canonical-parser-frontend=$canonical_frontend"
        echo "canonical-parser-implementation=$canonical_parser"
    else
        echo "canonical-parser-source-present=NO"
    fi
    if [ -n "$check_branch" ] || [ -n "$generated_stub" ]; then
        echo "entry=generated-stage1-main-check-branch"
        echo "entry-source=${check_branch:-$generated_stub}"
    else
        echo "entry=UNKNOWN"
    fi
    if [ -n "$generated_stub" ]; then
        echo "source-loader=stage1-read_file"
        echo "source-loader-source=$generated_stub"
        echo "parser-entry=NONE"
        echo "s-parser-reached=NO"
        echo "wiring-target=canonical-s-parser"
        echo "wiring-status=NOT_WIRED"
        echo "diagnostic-source=stage1-check-stub"
    else
        echo "source-loader=UNKNOWN"
        echo "parser-entry=UNKNOWN"
        echo "s-parser-reached=UNKNOWN"
        echo "wiring-target=canonical-s-parser"
        echo "wiring-status=UNKNOWN"
        echo "diagnostic-source=UNKNOWN"
    fi
    if [ -n "$stage2_stub" ]; then
        echo "fallback=generated-stage2-check-stub"
        echo "fallback-source=$stage2_stub"
    else
        echo "fallback=NONE_DETECTED"
    fi
    if grep -Eq 's_seed|SEED_COMPILER|bin/s_seed' "$compiler" 2>/dev/null; then
        echo "seed-delegation=DETECTED"
    else
        echo "seed-delegation=NONE"
    fi
    if [ "$reject_status" -eq 0 ] && [ -n "$generated_stub" ]; then
        echo "result=BLOCKED"
        echo "reason=check-command-stops-at-stage1-read-file-stub-before-canonical-s-parser"
        echo "gap=BOOTSTRAP_CAPABILITY_GAP"
        echo "next-cut=stage1-must-carry-or-invoke-canonical-s-parser-without-stage0-parser-authority"
    elif [ "$reject_status" -eq 0 ]; then
        echo "result=BLOCKED"
        echo "reason=negative-fixture-accepted-but-static-dispatch-node-not-located"
    else
        echo "result=TRACE_NEEDS_REVIEW"
        echo "reason=negative-fixture-rejected-but-parser-entry-not-proven-by-this-trace"
    fi
} >"$report"

cat "$report"
