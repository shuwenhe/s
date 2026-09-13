#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-nll-shadow.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

check_shadow() {
    name=$1
    source=$2
    expected_points=$3
    src="$work/$name.s"
    out="$work/$name.shadow"
    printf '%s\n' "$source" >"$src"
    "$root/bin/s" --emit-mir-nll-shadow "$src" "$out"
    if grep -Fq 'NLLShadowMismatch' "$out"; then
        echo "mir nll shadow: $name diverged" >&2
        cat "$out" >&2
        exit 1
    fi
    if ! grep -Eq 'NLLShadowCheck\(loans=[0-9]+, move_points=[0-9]+, comparisons=[0-9]+, mismatches=0' "$out"; then
        echo "mir nll shadow: $name did not report a clean comparison" >&2
        cat "$out" >&2
        exit 1
    fi
    if ! grep -Fq "$expected_points" "$out"; then
        echo "mir nll shadow: $name did not report solver loan live points" >&2
        cat "$out" >&2
        exit 1
    fi
    if ! grep -Eq 'MovePoint\(P[0-9]+, Field\(_1, 0\)\)' "$out"; then
        echo "mir nll shadow: $name did not report move point details" >&2
        cat "$out" >&2
        exit 1
    fi
    if ! grep -Eq 'NLLShadowCompare\(L0, P[0-9]+, legacy_borrowed=(true|false), solver_borrowed=(true|false), result=MATCH\)' "$out"; then
        echo "mir nll shadow: $name did not compare legacy and solver decisions" >&2
        cat "$out" >&2
        exit 1
    fi
}

check_mismatch() {
    name=$1
    source=$2
    src="$work/$name.s"
    out="$work/$name.shadow"
    printf '%s\n' "$source" >"$src"
    "$root/bin/s" --emit-mir-nll-shadow "$src" "$out"
    if ! grep -Fq 'NLLShadowMismatch(' "$out"; then
        echo "mir nll shadow: $name should demonstrate solver independence with a mismatch" >&2
        cat "$out" >&2
        exit 1
    fi
    if ! grep -Eq 'NLLShadowCheck\(loans=[0-9]+, move_points=[0-9]+, comparisons=[0-9]+, mismatches=1' "$out"; then
        echo "mir nll shadow: $name mismatch count missing" >&2
        cat "$out" >&2
        exit 1
    fi
}

check_shadow "branch_asymmetric_use" 'package shadow
func main() int {
    borrow_shared_field p _1 0
    if cond {
        use_ref p
    } else {
    }
    move_field _1 0
    return 0
}' 'LoanLivePoints(L0) = {P0, P1}'

check_shadow "alias_one_branch_use" 'package shadow
func main() int {
    borrow_shared_field p _1 0
    q := p
    if cond {
        use_ref q
    } else {
    }
    move_field _1 0
    return 0
}' 'LoanLivePoints(L0) = {P0, P2}'

check_shadow "loop_backedge_use" 'package shadow
func main() int {
    borrow_shared_field p _1 0
    while cond {
        use_ref p
    }
    move_field _1 0
    return 0
}' 'LoanLivePoints(L0) = {P0, P1}'

check_shadow "nested_branch_loop_alias" 'package shadow
func main() int {
    borrow_shared_field p _1 0
    q := p
    while cond {
        if cond2 {
            use_ref q
        } else {
        }
    }
    move_field _1 0
    return 0
}' 'LoanLivePoints(L0) = {P0, P2}'

check_mismatch "legacy_token_overapproximates_dead_branch_alias" 'package shadow
func main() int {
    borrow_shared_field p _1 0
    q := p
    if cond {
        use_ref q
    } else {
    }
    move_field _1 0
    drop p
    return 0
}'

echo "MIR NLL shadow check passed"
