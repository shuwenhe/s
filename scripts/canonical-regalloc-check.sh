#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage18/canonical-regalloc-gate.txt"
PROOF_OUTPUT="${REPORT}.proof.$$"
TMP_REPORT="${REPORT}.tmp.$$"
TEST_FILE="${SOURCE_ROOT}/test/simple.s"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$PROOF_OUTPUT" "$TMP_REPORT"' EXIT HUP INT TERM

fail() {
    {
        echo "STAGE 18 - REGISTER ALLOCATION"
        echo "Scope: Stage 18 gate only; register allocation before machine code/object emission"
        echo "Machine code/object/link success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage18-regalloc-runtime-proof"
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

pass() {
    {
        cat "$PROOF_OUTPUT"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 0
}

# Verify compiler binary exists
if [ ! -x "$COMPILER" ]; then
    fail "S18.1" "compiler not found or not executable: $COMPILER"
    exit $?
fi

# Find a suitable test file
if [ ! -f "$TEST_FILE" ]; then
    TEST_FILE="${SOURCE_ROOT}/test/compiler/stage12_move_semantics_real.s"
fi

if [ ! -f "$TEST_FILE" ]; then
    TEST_FILE="${SOURCE_ROOT}/test/p0_pair_debug.s"
fi

if [ ! -f "$TEST_FILE" ]; then
    # Create a minimal test if none found
    TEST_FILE="/tmp/stage18_test_$$.s"
    cat > "$TEST_FILE" << 'TESTEOF'
package main

func main() {
    x := 1
    y := x + 2
    return 0
}
TESTEOF
    trap "rm -f '$PROOF_OUTPUT' '$TMP_REPORT' '$TEST_FILE'" EXIT HUP INT TERM
fi

# Run the runtime regalloc proof command
if ! "$COMPILER" canonical-regalloc-proof "$TEST_FILE" "$PROOF_OUTPUT" 2>/dev/null; then
    fail "S18.1" "canonical-regalloc-proof command failed"
    exit $?
fi

# Verify the output exists and is readable
if [ ! -f "$PROOF_OUTPUT" ]; then
    fail "S18.1" "proof output not generated"
    exit $?
fi

# Extract and validate proof results
S18_1=$(grep '^S18.1=' "$PROOF_OUTPUT" | head -1 | sed 's/^S18.1=//')
S18_2=$(grep '^S18.2=' "$PROOF_OUTPUT" | head -1 | sed 's/^S18.2=//')
S18_3=$(grep '^S18.3=' "$PROOF_OUTPUT" | head -1 | sed 's/^S18.3=//')
S18_4=$(grep '^S18.4=' "$PROOF_OUTPUT" | head -1 | sed 's/^S18.4=//')
S18_5=$(grep '^S18.5=' "$PROOF_OUTPUT" | head -1 | sed 's/^S18.5=//')
REGALLOC_STAGE=$(grep '^stage18-regalloc=' "$PROOF_OUTPUT" | head -1 | sed 's/^stage18-regalloc=//')
RESULT=$(grep '^result=' "$PROOF_OUTPUT" | head -1 | sed 's/^result=//')

# Verify S18.1 - Input Authority (canonical Stage 17 output)
if [ "$S18_1" != "PASS" ]; then
    fail "S18.1" "Stage 18 input authority proof failed"
    exit $?
fi

# Verify the input authority is correctly identified
INPUT_AUTH=$(grep '^S18.1.input-authority=' "$PROOF_OUTPUT" | sed 's/^S18.1.input-authority=//')
if [ "$INPUT_AUTH" != "stage17-codegen-canonical" ]; then
    fail "S18.1" "Stage 18 input authority not from Stage 17: $INPUT_AUTH"
    exit $?
fi

# Verify MIR input was consumed without reconstruction
MIR_CONSUMED=$(grep '^S18.1.mir-input-consumed=' "$PROOF_OUTPUT" | sed 's/^S18.1.mir-input-consumed=//')
RECONSTRUCTION=$(grep '^S18.1.reconstruction=' "$PROOF_OUTPUT" | sed 's/^S18.1.reconstruction=//')

if [ "$MIR_CONSUMED" != "yes" ]; then
    fail "S18.1" "MIR input not consumed: $MIR_CONSUMED"
    exit $?
fi

if [ "$RECONSTRUCTION" != "no" ]; then
    fail "S18.1" "MIR reconstruction not prevented: $RECONSTRUCTION"
    exit $?
fi

# Verify S18.2 - Allocator Execution (real production register allocator)
if [ "$S18_2" != "PASS" ]; then
    fail "S18.2" "Register allocator execution proof failed"
    exit $?
fi

# Verify the allocator was actually executed
ALLOCATOR_EXECUTED=$(grep '^S18.2.allocator-executed=' "$PROOF_OUTPUT" | sed 's/^S18.2.allocator-executed=//')
if [ "$ALLOCATOR_EXECUTED" != "yes" ]; then
    fail "S18.2" "Allocator did not execute: $ALLOCATOR_EXECUTED"
    exit $?
fi

# Verify it's the real linear scan allocator
ALLOCATOR_PRODUCER=$(grep '^S18.2.allocator-producer=' "$PROOF_OUTPUT" | sed 's/^S18.2.allocator-producer=//')
if [ "$ALLOCATOR_PRODUCER" != "compile.internal.middlend.ssa_core.linear_scan_regalloc_with_spill" ]; then
    fail "S18.2" "Real allocator not invoked: $ALLOCATOR_PRODUCER"
    exit $?
fi

# Verify S18.3 - Virtual Register Tracking
if [ "$S18_3" != "PASS" ]; then
    fail "S18.3" "Virtual register facts proof failed"
    exit $?
fi

# Extract virtual register count
VIRT_REGS=$(grep '^S18.2.virtual-registers-analyzed=' "$PROOF_OUTPUT" | sed 's/^S18.2.virtual-registers-analyzed=//')
if [ -z "$VIRT_REGS" ] || [ "$VIRT_REGS" -lt 0 ]; then
    fail "S18.3" "Invalid virtual register count: $VIRT_REGS"
    exit $?
fi

# Verify S18.4 - Physical Register and Spill Assignment
if [ "$S18_4" != "PASS" ]; then
    fail "S18.4" "Physical register and spill assignment proof failed"
    exit $?
fi

# Extract physical register/spill facts
PHYS_REGS=$(grep '^S18.2.physical-registers-used=' "$PROOF_OUTPUT" | sed 's/^S18.2.physical-registers-used=//')
SPILL_SLOTS=$(grep '^S18.4.spill-slots-allocated=' "$PROOF_OUTPUT" | sed 's/^S18.4.spill-slots-allocated=//')

if [ -z "$PHYS_REGS" ] || [ "$PHYS_REGS" -lt 0 ]; then
    fail "S18.4" "Invalid physical register count: $PHYS_REGS"
    exit $?
fi

if [ -z "$SPILL_SLOTS" ] || [ "$SPILL_SLOTS" -lt 0 ]; then
    fail "S18.4" "Invalid spill slot count: $SPILL_SLOTS"
    exit $?
fi

# Verify S18.5 - Quality Metrics
if [ "$S18_5" != "PASS" ]; then
    fail "S18.5" "Regalloc quality metrics proof failed"
    exit $?
fi

# Extract quality score
QUALITY=$(grep '^S18.5.quality-score=' "$PROOF_OUTPUT" | sed 's/^S18.5.quality-score=//')
RECON_CONFIRMED=$(grep '^S18.5.reconstruction-confirmed=' "$PROOF_OUTPUT" | sed 's/^S18.5.reconstruction-confirmed=//')

if [ "$RECON_CONFIRMED" != "no" ]; then
    fail "S18.5" "Reconstruction not confirmed as prevented: $RECON_CONFIRMED"
    exit $?
fi

# Verify final stage status
if [ "$REGALLOC_STAGE" != "CLOSED" ]; then
    fail "FINAL" "Stage 18 not properly closed: $REGALLOC_STAGE"
    exit $?
fi

if [ "$RESULT" != "PASS" ]; then
    fail "FINAL" "Register allocation proof did not pass: $RESULT"
    exit $?
fi

# All checks passed - output the proof report
pass
exit 0

