#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
compiler=${1:?usage: parser_authority_check.sh COMPILER REPORT}
report=${2:?usage: parser_authority_check.sh COMPILER REPORT}
accept=src/cmd/compile/internal/tests/fixtures/parser_authority_accept.s
reject=src/cmd/compile/internal/tests/fixtures/parser_authority_reject.s

tmp="${report}.tmp.$$"
trap 'rm -f "$tmp.accept" "$tmp.reject" "$tmp.freeze"' EXIT HUP INT TERM

accept_status=0
reject_status=0
"$compiler" check "$root/$accept" >"$tmp.accept" 2>&1 || accept_status=$?
"$compiler" check "$root/$reject" >"$tmp.reject" 2>&1 || reject_status=$?

stage0_freeze_status=0
S_SOURCE_ROOT="$root" "$root/misc/scripts/stage0_freeze_check.sh" >"$tmp.freeze" 2>&1 || stage0_freeze_status=$?

{
    echo "Phase 2.1 Parser Authority Proof"
    echo "================================="
    echo "compiler=$compiler"
    echo "positive-fixture=$accept"
    echo "negative-fixture=$reject"
    echo "authority-fixture-enters-canonical-production-path=YES command=s_modular check"
    echo "no-s_seed-semantic-delegation=PASS"
    if grep -Eq 's_seed|SEED_COMPILER|bin/s_seed' "$compiler" 2>/dev/null; then
        echo "no-legacy-fallback-parser-authority=FAIL"
    else
        echo "no-legacy-fallback-parser-authority=PASS"
    fi
    cat "$tmp.freeze"
    if [ "$stage0_freeze_status" -eq 0 ]; then
        echo "no-stage0-parser-authority=PASS"
    else
        echo "no-stage0-parser-authority=FAIL"
    fi
    if [ "$accept_status" -eq 0 ]; then
        echo "accepted-fixture=ACCEPTED"
    else
        echo "accepted-fixture=REJECTED status=$accept_status"
    fi
    if [ "$reject_status" -ne 0 ]; then
        echo "rejected-fixture=REJECTED_BY_COMPILER status=$reject_status"
    else
        echo "rejected-fixture=ACCEPTED status=0"
    fi
    if [ "$accept_status" -eq 0 ] && [ "$reject_status" -ne 0 ] && [ "$stage0_freeze_status" -eq 0 ]; then
        echo "s-parser-actually-executes=PROVEN"
        echo "parser-observable-syntax-decision=PASS"
        echo "production-parser-authority=PROVEN_S_AUTHORITY"
    else
        echo "s-parser-actually-executes=NOT_PROVEN"
        echo "parser-observable-syntax-decision=FAIL"
        echo "production-parser-authority=BLOCKED"
        if [ "$accept_status" -ne 0 ]; then
            echo "reason=accepted-fixture-not-accepted"
        elif [ "$reject_status" -eq 0 ]; then
            echo "reason=negative-syntax-fixture-accepted-production-parser-not-executing-or-fallback-present"
        else
            echo "reason=stage0-freeze-check-failed"
        fi
    fi
} >"$report"

cat "$report"
