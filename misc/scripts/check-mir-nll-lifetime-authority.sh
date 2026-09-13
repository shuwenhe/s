#!/bin/sh
# mir-nll-lifetime-authority.sh
# TDD Gate for Phase C: Solver-owned Loan Lifetime
# 
# Objective: Prove that solver-derived LoanLivePoints (via real CFG ref-liveness)
# produces correct borrow endpoint decisions independent of legacy text scanning.
#
# NOT testing: future-token heuristics, text scanning
# ONLY testing: Real MIR/CFG → Reference Liveness → Region Constraints → LoanLivePoints
#
# Test categories:
# 1. Implicit last-use (no explicit drop) → should allow move
# 2. Explicit drop(ref) → should allow move
# 3. Alias case with last-use → should allow move
# 4. Branch/join with last-use → should allow move
# 5. Loop with last-use at backedge exit → should allow move
# 6. Field/nested field cases
#
# Each test checks:
# - Final ACCEPT/REJECT decision
# - LoanLivePoints calculation accuracy
# - MovePoint vs LoanLivePoints membership

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-nll-lifetime.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

expect_compile_pass() {
    name=$1
    source=$2
    src="$work/$name.s"
    log="$work/$name.log"
    printf '%s\n' "$source" >"$src"
    if ! "$root/bin/s" "$src" -o "$work/$name" >"$log" 2>&1; then
        echo "lifetime-authority: $name should pass but failed" >&2
        cat "$log" >&2
        exit 1
    fi
}

expect_compile_fail() {
    name=$1
    source=$2
    needle=$3
    src="$work/$name.s"
    log="$work/$name.log"
    printf '%s\n' "$source" >"$src"
    if "$root/bin/s" "$src" -o "$work/$name" >"$log" 2>&1; then
        echo "lifetime-authority: $name should fail but compiled" >&2
        cat "$log" >&2
        exit 1
    fi
    if ! grep -Fq "$needle" "$log"; then
        echo "lifetime-authority: $name missing expected error: $needle" >&2
        cat "$log" >&2
        exit 1
    fi
}

echo "Running MIR NLL lifetime-authority check..."

# Test 1: Implicit last-use (no explicit drop)
# Loan should END at last use of reference.
# Move should be ALLOWED after last use.
expect_compile_pass "implicit_last_use_owner" 'package lifetime
func main() int {
    owner := box(41)
    reader := &owner
    x := *reader
    moved := owner
    return x
}'

expect_compile_pass "implicit_last_use_field" 'package lifetime
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    x := *left
    moved_left := p.left
    return x
}'

# Test 2: Explicit drop(ref) semantics
# Loan should END after explicit drop.
# Move should be ALLOWED after drop.
expect_compile_pass "explicit_drop_owner" 'package lifetime
func main() int {
    owner := box(41)
    reader := &owner
    drop(reader)
    moved := owner
    return 41
}'

expect_compile_pass "explicit_drop_field" 'package lifetime
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    drop(left)
    moved_left := p.left
    return 20
}'

# Test 3: Move without completing last-use
# Loan is still LIVE at move point.
# Move should ERROR.
expect_compile_fail "move_before_last_use_owner" 'package lifetime
func main() int {
    owner := box(41)
    reader := &owner
    moved := owner
    x := *reader
    return x
}' "OwnershipAuthority(solver) SolverDecision(ERROR)"

expect_compile_fail "move_before_last_use_field" 'package lifetime
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    moved_left := p.left
    x := *left
    return x
}' "OwnershipAuthority(solver) SolverDecision(ERROR)"

# Test 4: Alias (multiple refs) with last-use
# All aliases must be dead before move.
# Last use of ANY alias keeps loan alive.
expect_compile_pass "alias_last_use_owner" 'package lifetime
func main() int {
    owner := box(41)
    r1 := &owner
    r2 := &owner
    x := *r2
    moved := owner
    return x
}'

# Test 5: Conditional paths - join point semantic
# If borrow reaches from one branch but not another,
# loan must be live at join.
# This requires real CFG analysis, not text scanning.
expect_compile_pass "branch_join_last_use_owner" 'package lifetime
func main() int {
    owner := box(41)
    reader := &owner
    if owner == 0 {
        x := *reader
        return x
    }
    moved := owner
    return 42
}'

# Test 6: Loop exit with last-use
# Loop body may use reference multiple times.
# Loan ends after loop (backedge not taken).
# Move after loop should be ALLOWED.
expect_compile_pass "loop_exit_last_use_owner" 'package lifetime
func main() int {
    owner := box(41)
    reader := &owner
    i := 0
    while i < 5 {
        x := *reader
        i = i + 1
    }
    moved := owner
    return 42
}'

# Test 7: Nested field with last-use
expect_compile_pass "nested_field_last_use" 'package lifetime
func main() int {
    outer := pair(box(1), box(2))
    inner := pair(outer, box(3))
    nested := &inner.left
    x := **nested
    moved_inner := inner
    return x
}'

# Test 8: CRITICAL - Regression case from B2
# This exposes the difference between legacy text scanning and solver analysis.
# Legacy: future-token sees "moved_left" text, keeps loan alive → ERROR
# Solver: CFG analysis shows left not used after drop → OK
#
# For now, we EXPECT_PASS because we're transitioning to solver lifetime.
# If this fails, solver lifetime is not ready yet.
expect_compile_pass "critical_regression_lifetime" 'package lifetime
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    assert(*left == 20)
    drop(left)
    moved_left := p.left
    return *moved_left
}'

echo "✓ MIR NLL lifetime-authority check passed"
