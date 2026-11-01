#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-nll-no-legacy-auth.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

expect_compile_fail() {
    name=$1
    source=$2
    needle=$3
    src="$work/$name.s"
    log="$work/$name.log"
    printf '%s\n' "$source" >"$src"
    if "$root/bin/s" "$src" -o "$work/$name" >"$log" 2>&1; then
        echo "no-legacy-authority: $name should fail but compiled" >&2
        cat "$log" >&2
        exit 1
    fi
    if ! grep -Fq "$needle" "$log"; then
        echo "no-legacy-authority: $name missing expected diagnostic: $needle" >&2
        cat "$log" >&2
        exit 1
    fi
}

expect_compile_pass() {
    name=$1
    source=$2
    src="$work/$name.s"
    log="$work/$name.log"
    printf '%s\n' "$source" >"$src"
    if ! "$root/bin/s" "$src" -o "$work/$name" >"$log" 2>&1; then
        echo "no-legacy-authority: $name should pass but failed" >&2
        cat "$log" >&2
        exit 1
    fi
}

echo "Running MIR NLL no-legacy-authority check..."

expect_compile_fail "solver_error_legacy_ok_must_reject" 'package authority
func main() int {
    owner := box(41)
    reader := &owner
    // nll_solver_force_live reader
    moved := owner
    return 0
}' "OwnershipAuthority(solver) SolverDecision(ERROR)"

expect_compile_pass "solver_ok_legacy_error_must_accept" 'package authority
func main() int {
    owner := box(41)
    reader := &owner
    // nll_solver_force_dead reader
    moved := owner
    return *moved
}'

expect_compile_fail "field_inversion_solver_error_legacy_ok" 'package authority
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    // nll_solver_force_live left
    moved_left := p.left
    return *moved_left
}' "OwnershipAuthority(solver) SolverDecision(ERROR)"

expect_compile_pass "field_inversion_solver_ok_legacy_error" 'package authority
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    // nll_solver_force_dead left
    moved_left := p.left
    return *moved_left
}'

expect_compile_fail "nested_inversion_solver_error_legacy_ok" 'package authority
struct Left { data box }
struct Right { data box }
struct Inner { left Left; right Right }
struct Outer { inner Inner; tail Right }
func main() int {
    p := Outer(Inner(Left(box(1)), Right(box(2))), Right(box(3)))
    r := &p.inner.left
    // nll_solver_force_live r
    x := p.inner.left
    return 0
}' "OwnershipAuthority(solver) SolverDecision(ERROR)"

expect_compile_pass "nested_inversion_solver_ok_legacy_error" 'package authority
struct Left { data box }
struct Right { data box }
struct Inner { left Left; right Right }
struct Outer { inner Inner; tail Right }
func main() int {
    p := Outer(Inner(Left(box(1)), Right(box(2))), Right(box(3)))
    r := &p.inner.left
    // nll_solver_force_dead r
    x := p.inner.left
    return 0
}'

echo "✓ MIR NLL no-legacy-authority check passed"
