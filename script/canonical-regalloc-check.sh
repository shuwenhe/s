#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
REGRESSION="${SOURCE_ROOT}/test/native-codegen/check.sh"
REPORT="${SOURCE_ROOT}/.bootstrap/stage18/canonical-regalloc-gate.txt"
REGRESSION_LOG="${REPORT}.native-codegen.log"
TMP_REPORT="${REPORT}.tmp.$$"
ARTIFACTS=""

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$TMP_REPORT"' EXIT HUP INT TERM

header() {
    echo "STAGE 18 - REGISTER / STACK ASSIGNMENT"
    echo "scope=P0 Native Linux/amd64"
    echo "selfhost=NOT_PROVEN"
    echo "proof-source=test/native-codegen/check.sh"
    echo "regression-command=bash $REGRESSION"
    echo "regression-log=$REGRESSION_LOG"
    echo "allocator-producer=compile.internal.amd64_slot/amd64_emit_function"
    echo "allocator-source=src/cmd/compile/internal/codegen/amd64_program.s"
    echo "allocator-type=position-based-stack-slots"
    if [ -n "$ARTIFACTS" ]; then
        echo "native-codegen-artifacts=$ARTIFACTS"
        echo "input-hashes=$ARTIFACTS/input-hashes.txt"
    fi
}

fail() {
    {
        header
        echo "$1=FAIL"
        echo "$1.reason=$2"
        echo "first-unmet-contract=$1"
        echo "stage18-regalloc=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

# This suite compiles the production SSA and AMD64 modules, assembles their
# output, and executes the resulting objects and standalone ELF programs.
# Its checks cover position-based frames and values live across ABI calls.
if [ ! -f "$REGRESSION" ]; then
    fail "S18.1" "native codegen regression not found: $REGRESSION"
fi

REGRESSION_STATUS=0
timeout "${S_NATIVE_CODEGEN_GATE_TIMEOUT:-120}s" bash "$REGRESSION" > "$REGRESSION_LOG" 2>&1 || REGRESSION_STATUS=$?
ARTIFACTS=$(sed -n 's/^Native SSA codegen artifacts=//p' "$REGRESSION_LOG" | tail -n 1)
if [ "$REGRESSION_STATUS" -ne 0 ]; then
    fail "S18.2" "native codegen regression exited $REGRESSION_STATUS; see $REGRESSION_LOG"
fi

# An empty or partial successful command is not behavioral evidence. Require
# every success marker emitted only after the regression's checks complete.
if ! grep -Fqx 'SSA -> S AMD64 instruction selection -> GNU as ELF object -> ABI harness: PASS' "$REGRESSION_LOG"; then
    fail "S18.3" "native object execution success marker missing; see $REGRESSION_LOG"
fi
if ! grep -Fqx 'Register/stack parameters, calls/live values, signed arithmetic, rejection and ELF checks: PASS' "$REGRESSION_LOG"; then
    fail "S18.4" "register/stack and live-value success marker missing; see $REGRESSION_LOG"
fi
if ! grep -Fqx 'GNU ld standalone startup, strict runtime int64 argv and no dynamic dependencies: PASS' "$REGRESSION_LOG"; then
    fail "S18.5" "standalone ELF startup success marker missing; see $REGRESSION_LOG"
fi

{
    header
    echo "S18.1=PASS"
    echo "S18.1.input-authority=function_ssa_program"
    echo "S18.1.input-source=test/native-codegen/generate.s"
    echo "S18.2=PASS"
    echo "S18.2.allocator-executed=yes"
    echo "S18.2.allocator-producer=compile.internal.amd64_slot/amd64_emit_function"
    echo "S18.2.allocator-type=position-based-stack-slots"
    echo "S18.2.regression-exit=0"
    echo "S18.3=PASS"
    echo "S18.3.evidence=generated ELF objects execute with expected results"
    echo "S18.4=PASS"
    echo "S18.4.evidence=register and stack arguments, live values across calls, stack alignment, sparse SSA ID frame check"
    echo "S18.5=PASS"
    echo "S18.5.evidence=standalone ELF startup and strict int64 argv behavior"
    echo "stage18-regalloc=CLOSED"
    echo "result=PASS"
} > "$TMP_REPORT"
mv "$TMP_REPORT" "$REPORT"
cat "$REPORT"
