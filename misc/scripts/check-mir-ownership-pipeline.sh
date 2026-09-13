#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-mir-ownership-pipeline.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

export S_MODULAR_COMPILER=/nonexistent/s_modular

compile_and_run() {
    name=$1
    expected=$2
    source=$3

    src="$work/$name.s"
    exe="$work/$name"
    c_out="$work/$name.c"
    printf '%s\n' "$source" >"$src"

    S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" --emit-c "$src" "$c_out"
    S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$src" -o "$exe"

    set +e
    "$exe"
    status=$?
    set -e
    if [ "$status" -ne "$expected" ]; then
        echo "mir ownership pipeline: $name exited $status, expected $expected" >&2
        exit 1
    fi
}

reject_compile() {
    name=$1
    source=$2
    pattern=$3

    src="$work/$name.s"
    exe="$work/$name"
    c_out="$work/$name.c"
    err="$work/$name.err"
    printf '%s\n' "$source" >"$src"
    printf 'sentinel' >"$c_out"

    if S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$src" -o "$exe" >/dev/null 2>"$err"; then
        echo "mir ownership pipeline: $name unexpectedly compiled" >&2
        exit 1
    fi
    if [ -e "$exe" ]; then
        echo "mir ownership pipeline: $name produced an executable after rejection" >&2
        exit 1
    fi
    if ! grep -Eq "$pattern" "$err"; then
        echo "mir ownership pipeline: $name diagnostic did not match $pattern" >&2
        cat "$err" >&2
        exit 1
    fi
    if [ "$(cat "$c_out")" != "sentinel" ]; then
        echo "mir ownership pipeline: $name overwrote an output after rejection" >&2
        exit 1
    fi
}

compile_and_run "move_after_last_reference_use" 42 'package ownpipe

func main() int {
    owner := box(41)
    reader := &owner
    assert(*reader == 41)
    moved := owner
    return *moved + live_allocations()
}'

compile_and_run "alias_last_reference_use" 42 'package ownpipe

func main() int {
    owner := box(41)
    p := &owner
    q := p
    assert(*q == 41)
    moved := owner
    return *moved + live_allocations()
}'

compile_and_run "branch_reference_dead_at_join" 42 'package ownpipe

func main() int {
    owner := box(41)
    p := &owner
    if live_allocations() == 1 {
        assert(*p == 41)
    } else {
    }
    moved := owner
    return *moved + live_allocations()
}'

compile_and_run "loop_reference_dead_after_loop" 42 'package ownpipe

func main() int {
    owner := box(41)
    p := &owner
    i := 0
    while i < 1 {
        assert(*p == 41)
        i = i + 1
    }
    moved := owner
    return *moved + live_allocations()
}'

compile_and_run "partial_scope_drop" 42 'package ownpipe

func main() int {
    {
        owner := box(42)
        moved := owner
        assert(*moved == 42)
        assert(live_allocations() == 1)
    }
    assert(live_allocations() == 0)
    return 42
}'

compile_and_run "move_reinit_drop" 42 'package ownpipe

func main() int {
    {
        owner := box(40)
        moved := owner
        assert(*moved == 40)
        owner = box(2)
        assert(*owner == 2)
        assert(live_allocations() == 2)
    }
    assert(live_allocations() == 0)
    return 42
}'

compile_and_run "partial_place_sibling_move" 42 'package ownpipe

func main() int {
    {
        p := pair(box(20), box(21))
        left := &p.left
        right := p.right
        assert(*left == 20)
        assert(*right == 21)
        assert(live_allocations() == 3)
    }
    assert(live_allocations() == 0)
    return 42
}'

reject_compile "use_after_move" 'package ownpipe_bad

func main() int {
    owner := box(1)
    moved := owner
    return *owner
}' 'move|moved|ownership|borrow'

reject_compile "double_move" 'package ownpipe_bad

func main() int {
    owner := box(1)
    left := owner
    right := owner
    return *left
}' 'move|moved|ownership|borrow'

reject_compile "move_while_borrowed" 'package ownpipe_bad

func main() int {
    owner := box(1)
    reader := &owner
    moved := owner
    return *reader
}' 'borrow|move|moved|ownership'

reject_compile "move_before_last_reference_use" 'package ownpipe_bad

func main() int {
    owner := box(1)
    reader := &owner
    moved := owner
    return *reader
}' 'borrow|move|moved|ownership'

reject_compile "partial_place_borrowed_field_move" 'package ownpipe_bad

func main() int {
    p := pair(box(20), box(21))
    left := &p.left
    moved_left := p.left
    return *left + *moved_left
}' 'borrow|move|moved|ownership'

reject_compile "assign_while_borrowed" 'package ownpipe_bad

func main() int {
    owner := box(1)
    reader := &owner
    owner = box(2)
    return *reader
}' 'borrow|move|assign|ownership'

echo "Real MIR ownership pipeline gate passed"
