#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-nll-shadow.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

check_shadow() {
    name=$1
    source=$2
    src="$work/$name.s"
    out="$work/$name.shadow"
    printf '%s\n' "$source" >"$src"
    "$root/bin/s" --emit-mir-nll-shadow "$src" "$out"
    if grep -Fq 'NLLShadowMismatch' "$out"; then
        echo "mir nll shadow: $name diverged" >&2
        cat "$out" >&2
        exit 1
    fi
    if ! grep -Fq 'NLLShadowCheck(mismatches=0' "$out"; then
        echo "mir nll shadow: $name did not report a clean comparison" >&2
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
}'

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
}'

check_shadow "loop_backedge_use" 'package shadow
func main() int {
    borrow_shared_field p _1 0
    while cond {
        use_ref p
    }
    move_field _1 0
    return 0
}'

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
}'

echo "MIR NLL shadow check passed"
