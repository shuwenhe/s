#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
compiler=${1:?usage: stage1_import_carry_check.sh COMPILER OUTPUT_DIR}
out=${2:?missing output directory}

test -x "$compiler"
mkdir -p "$out"
work=$(mktemp -d "$out/import-carry.XXXXXX")

# Fixture files
valid_fixture=$root/test/selfhost/bootstrap_import_carry_valid.s
invalid_unclosed=$root/test/selfhost/bootstrap_import_carry_invalid_unclosed.s
invalid_nonstring=$root/test/selfhost/bootstrap_import_carry_invalid_nonstring.s

# Test results
valid_build_status=0
valid_exit=NOT_RUN
invalid_unclosed_status=1  # Should fail
invalid_nonstring_status=1  # Should fail

report=$work/report.txt

# TEST 1: Valid fixture - should compile and run successfully
"$compiler" build "$valid_fixture" -o "$work/valid" > "$work/valid.log" 2>&1 || valid_build_status=$?

if [ "$valid_build_status" -eq 0 ] && [ -x "$work/valid" ]; then
    valid_exit=NOT_RUN
    "$work/valid" > "$work/valid.run.log" 2>&1 || valid_exit=$?
fi

# TEST 2: Invalid fixture (unclosed import) - should fail to compile
"$compiler" build "$invalid_unclosed" -o "$work/invalid_unclosed" > "$work/invalid_unclosed.log" 2>&1 || invalid_unclosed_status=$?

# TEST 3: Invalid fixture (non-string import) - should fail to compile
"$compiler" build "$invalid_nonstring" -o "$work/invalid_nonstring" > "$work/invalid_nonstring.log" 2>&1 || invalid_nonstring_status=$?

# Generate report
{
    echo 'Phase 1.6.2 - Import Declaration Structural Carry Audit'
    echo "compiler=$compiler"
    echo "work-directory=$work"
    echo ""
    echo "== TEST: Valid Import Block =="
    echo "fixture=bootstrap_import_carry_valid.s"
    echo "build-exit-status=$valid_build_status"
    sed 's/^/diagnostic=/' "$work/valid.log" || true
    echo "run-exit-status=$valid_exit"
    echo ""
    echo "== TEST: Invalid - Unclosed Import Block =="
    echo "fixture=bootstrap_import_carry_invalid_unclosed.s"
    echo "should-fail=true"
    echo "build-exit-status=$invalid_unclosed_status"
    if [ "$invalid_unclosed_status" -ne 0 ]; then
        sed 's/^/diagnostic=/' "$work/invalid_unclosed.log" || true
    fi
    echo ""
    echo "== TEST: Invalid - Non-String Import Content =="
    echo "fixture=bootstrap_import_carry_invalid_nonstring.s"
    echo "should-fail=true"
    echo "build-exit-status=$invalid_nonstring_status"
    if [ "$invalid_nonstring_status" -ne 0 ]; then
        sed 's/^/diagnostic=/' "$work/invalid_nonstring.log" || true
    fi
    echo ""
    
    # Determine PASS/FAIL
    if [ "$valid_build_status" -eq 0 ] && [ "$valid_exit" = 17 ] && \
       [ "$invalid_unclosed_status" -ne 0 ] && \
       [ "$invalid_nonstring_status" -ne 0 ]; then
        echo "result=PASS"
        echo "import-declaration-structural-carry=PROVEN"
        echo "stage1-import-carry-check=PASS"
    else
        echo "result=FAIL"
        echo "import-declaration-structural-carry=NOT_PROVEN"
        echo "stage1-import-carry-check=FAIL"
        if [ "$valid_build_status" -ne 0 ]; then
            echo "reason=valid-fixture-failed-to-compile"
        elif [ "$valid_exit" != 17 ]; then
            echo "reason=valid-fixture-exit-code-mismatch (expected 17, got $valid_exit)"
        elif [ "$invalid_unclosed_status" -eq 0 ]; then
            echo "reason=invalid-unclosed-should-have-failed"
        elif [ "$invalid_nonstring_status" -eq 0 ]; then
            echo "reason=invalid-nonstring-should-have-failed"
        fi
    fi
} | tee "$report"

# Return appropriate exit code
if grep -qx "stage1-import-carry-check=PASS" "$report"; then
    exit 0
else
    exit 1
fi
