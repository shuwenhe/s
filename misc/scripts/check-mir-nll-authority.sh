#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-nll-authority.XXXXXXXX")
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
        echo "mir nll authority: $name unexpectedly compiled" >&2
        cat "$log" >&2
        exit 1
    fi
    if ! grep -Fq "$needle" "$log"; then
        echo "mir nll authority: $name missing diagnostic: $needle" >&2
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
        echo "mir nll authority: $name should compile under solver authority" >&2
        cat "$log" >&2
        exit 1
    fi
}

expect_compile_fail "solver_error_legacy_ok" 'package authority
func main() int {
    owner := box(41)
    reader := &owner
    assert(*reader == 41)
    // nll_solver_force_live reader
    moved := owner
    return 0
}' 'OwnershipAuthority(solver) SolverDecision(ERROR) LegacyShadow(OK)'

expect_compile_pass "solver_ok_legacy_error" 'package authority
func main() int {
    owner := box(41)
    reader := &owner
    // nll_solver_force_dead reader
    moved := owner
    return *moved
}'

expect_compile_fail "field_solver_error" 'package authority
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    moved_left := p.left
    return *left + *moved_left
}' 'OwnershipAuthority(solver) SolverDecision(ERROR)'

expect_compile_pass "field_sibling_solver_ok" 'package authority
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    moved_right := p.right
    assert(*left == 20)
    return *moved_right
}'

expect_compile_pass "field_after_last_use_solver_ok" 'package authority
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    assert(*left == 20)
    drop(left)
    moved_left := p.left
    return *moved_left
}'

expect_compile_fail "nested_solver_error" 'package authority
struct Left { data box }
struct Right { data box }
struct Inner { left Left; right Right }
struct Outer { inner Inner; tail Right }
func main() int {
    p := Outer(Inner(Left(box(1)), Right(box(2))), Right(box(3)))
    r := &p.inner.left
    x := p.inner.left
    return 0
}' 'OwnershipAuthority(solver) SolverDecision(ERROR)'

expect_compile_pass "nested_sibling_solver_ok" 'package authority
struct Left { data box }
struct Right { data box }
struct Inner { left Left; right Right }
struct Outer { inner Inner; tail Right }
func main() int {
    p := Outer(Inner(Left(box(1)), Right(box(2))), Right(box(3)))
    r := &p.inner.left
    x := p.inner.right
    return 0
}'

expect_compile_pass "nested_after_last_use_solver_ok" 'package authority
struct Left { data box }
struct Right { data box }
struct Inner { left Left; right Right }
struct Outer { inner Inner; tail Right }
func main() int {
    p := Outer(Inner(Left(box(1)), Right(box(2))), Right(box(3)))
    r := &p.inner.left
    drop(r)
    x := p.inner.left
    return 0
}'

expect_compile_pass "field_solver_error_legacy_ok" 'package authority
func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    drop(left)
    moved_left := p.left
    return *moved_left
}'

expect_compile_pass "nested_solver_ok_legacy_error" 'package authority
struct Left { data box }
struct Right { data box }
struct Inner { left Left; right Right }
struct Outer { inner Inner; tail Right }
func main() int {
    p := Outer(Inner(Left(box(1)), Right(box(2))), Right(box(3)))
    r := &p.inner.left
    x := p.inner.right
    return 0
}'

echo "MIR NLL authority check passed"
