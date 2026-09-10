#!/bin/sh
set -eu



root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

work=$(mktemp -d "${TMPDIR:-/tmp}/s-nogc-check.XXXXXXXX")

trap 'rm -rf "$work"' EXIT HUP INT TERM



cat >"$work/ownership.s" <<'SRC'

package ownership

func main() int {

    owner := box(20);

    {

        reference := &mut owner;

        *reference = *reference + 1;

    }

    moved := owner;

    {

        first := &moved;

        second := &moved;

        assert(*first == *second);

    }

    moved = box(*moved * 2);

    return *moved;

}

SRC



cat >"$work/hello.s" <<'SRC'

package main

func main() {

    println("Hello, world!")

    return

}

SRC



cat >"$work/reject.s" <<'SRC'

package bad

func main() int {

    a := box(1);

    r := &a;

    drop(a);

    return *r;

}

SRC



cat >"$work/string_helper.s" <<'SRC'

package strings

func say(string message) {

    println(message)

}

func main() {

    message := "Hello from helper"

    say(message)

    return

}

SRC



cat >"$work/struct_pair.s" <<'SRC'

package structs

struct Pair {

    first box

    second box

}

struct Duo {

    left box

    right box

}

func sum(Pair p) int {

    return *p.first + *p.second

}

func duo_sum(Duo d) int {

    return *d.left + *d.right

}

func main() int {

    {

        p := Pair(box(20), box(22))

        q := &p.first

        assert(*q == 20)

        drop(q)

        *p.second = 22

        assert(sum(p) == 42)

        d := Duo(box(1), box(2))

        assert(duo_sum(d) == 3)

    }

    assert(live_allocations() == 0)

    return 42

}

SRC



cat >"$work/early_return_cleanup.s" <<'SRC'

package early

func main() int {

    outer := box(1)

    inner := box(2)

    if *outer == 1 {

        return 42

    }

    drop(inner)

    drop(outer)

    return 1

}

SRC



cat >"$work/loop_cleanup.s" <<'SRC'

package loops

func main() int {

    i := 0

    while i < 4 {

        item := box(i)

        i = i + 1

        if i == 2 {

            continue

        }

        if i == 3 {

            break

        }

        drop(item)

    }

    assert(live_allocations() == 0)

    return 42

}

SRC



cat >"$work/conditional_move_cleanup.s" <<'SRC'

package conditional

func take(box value) int {

    return *value

}

func main() int {

    owner := box(42)

    if live_allocations() == 1 {

        moved := owner

        assert(take(moved) == 42)

    }

    assert(live_allocations() == 0)

    return 42

}

SRC



cat >"$work/drop_flag_elision.s" <<'SRC'

package flags

func main() int {

    first := box(1)

    second := first

    third := second

    return *third + 41

}

SRC



cat >"$work/custom_drop_scope_exit.s" <<'SRC'

package custom

struct Resource { first box; second box }

func (Resource* r) drop() {

    println("drop-resource")

}

func main() int {

    a := Resource(box(1), box(2))

    return 42

}

SRC



cat >"$work/custom_drop_lifo.s" <<'SRC'

package custom

struct A { first box; second box }

struct B { first box; second box }

func (A* a) drop() { println("drop-a") }

func (B* b) drop() { println("drop-b") }

func main() int {

    a := A(box(1), box(2))

    b := B(box(3), box(4))

    return 42

}

SRC



cat >"$work/custom_drop_move.s" <<'SRC'

package custom

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-moved") }

func main() int {

    a := Resource(box(1), box(2))

    b := a

    return 42

}

SRC



cat >"$work/custom_drop_conditional_move.s" <<'SRC'

package custom

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-conditional") }

func main() int {

    a := Resource(box(1), box(2))

    if live_allocations() == 3 {

        b := a

        assert(*b.first == 1)

    }

    assert(live_allocations() == 0)

    return 42

}

SRC



cat >"$work/custom_drop_early_return.s" <<'SRC'

package custom

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-early") }

func main() int {

    a := Resource(box(1), box(2))

    return 42

}

SRC



cat >"$work/custom_drop_loop_break.s" <<'SRC'

package custom

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-break") }

func main() int {

    i := 0

    while i < 1 {

        r := Resource(box(1), box(2))

        break

    }

    assert(live_allocations() == 0)

    return 42

}

SRC



cat >"$work/custom_drop_loop_continue.s" <<'SRC'

package custom

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-continue") }

func main() int {

    i := 0

    while i < 1 {

        r := Resource(box(1), box(2))

        i = i + 1

        continue

    }

    assert(live_allocations() == 0)

    return 42

}

SRC



cat >"$work/overwrite_live_owner.s" <<'SRC'

package overwrite

func main() int {

    a := box(1)

    a = box(42)

    return *a

}

SRC



cat >"$work/overwrite_custom_drop.s" <<'SRC'

package overwrite

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-resource") }

func main() int {

    a := Resource(box(1), box(2))

    a = Resource(box(3), box(4))

    return 42

}

SRC



cat >"$work/overwrite_moved_owner.s" <<'SRC'

package overwrite

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-moved-reinit") }

func main() int {

    a := Resource(box(1), box(2))

    b := a

    a = Resource(box(3), box(4))

    return 42

}

SRC



cat >"$work/overwrite_conditional_true.s" <<'SRC'

package overwrite

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-conditional-true") }

func main() int {

    a := Resource(box(1), box(2))

    if true {

        b := a

    }

    a = Resource(box(3), box(4))

    return 42

}

SRC



cat >"$work/overwrite_conditional_false.s" <<'SRC'

package overwrite

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-conditional-false") }

func main() int {

    a := Resource(box(1), box(2))

    if false {

        b := a

    }

    a = Resource(box(3), box(4))

    return 42

}

SRC



cat >"$work/overwrite_inside_loop.s" <<'SRC'

package overwrite

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-loop") }

func main() int {

    a := Resource(box(0), box(0))

    i := 0

    while i < 2 {

        a = Resource(box(i), box(i))

        i = i + 1

    }

    return 42

}

SRC



cat >"$work/overwrite_early_return.s" <<'SRC'

package overwrite

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-early-overwrite") }

func main() int {

    a := Resource(box(1), box(2))

    a = Resource(box(3), box(4))

    return 42

}

SRC



cat >"$work/rhs_before_lhs_drop.s" <<'SRC'

package overwrite

struct Resource { first box; second box }

func (Resource* r) drop() { println("drop-after-rhs") }

func make_resource() Resource {

    println("make-rhs")

    return Resource(box(3), box(4))

}

func main() int {

    a := Resource(box(1), box(2))

    a = make_resource()

    return 42

}

SRC



cat >"$work/struct_owned_fields_scope_exit.s" <<'SRC'

package fields

struct Pair { left box; right box }

func main() int {

    {

        p := Pair(box(1), box(2))

        assert(live_allocations() == 3)

    }

    assert(live_allocations() == 0)

    return 42

}

SRC



cat >"$work/struct_owned_fields_early_return.s" <<'SRC'

package fields

struct Pair { left box; right box }

func main() int {

    p := Pair(box(1), box(2))

    return 42

}

SRC



cat >"$work/struct_owned_fields_loop.s" <<'SRC'

package fields

struct Pair { left box; right box }

func main() int {

    i := 0

    while i < 2 {

        p := Pair(box(i), box(i))

        assert(live_allocations() == 3)

        i = i + 1

    }

    assert(live_allocations() == 0)

    return 42

}

SRC



cat >"$work/struct_custom_drop_with_fields.s" <<'SRC'

package fields

struct Pair { left box; right box }

func (Pair* p) drop() { println("Pair.drop") }

func main() int {

    p := Pair(box(1), box(2))

    return 42

}

SRC



cat >"$work/general_struct_three_fields.s" <<'SRC'

package fields

struct Triple { a box; b box; c box }

func main() int {

    t := Triple(box(1), box(2), box(39))

    assert(live_allocations() == 4)

    return *t.c + 3

}

SRC



cat >"$work/mixed_struct_fields.s" <<'SRC'

package fields

struct Resource { id int; data box; active bool }

func main() int {

    r := Resource(7, box(35), true)

    assert(r.id == 7)

    assert(r.active == true)

    return *r.data + 7

}

SRC



cat >"$work/nested_owned_struct.s" <<'SRC'

package fields

struct Inner { left box; right box }

struct Outer { inner Inner; tail box }

func main() int {

    o := Outer(Inner(box(1), box(2)), box(3))

    assert(live_allocations() == 5)

    return 42

}

SRC



cat >"$work/nested_custom_drop_order.s" <<'SRC'

package fields

struct Inner { left box; right box }

struct Outer { inner Inner; tail box }

func (Inner* inner) drop() { println("Inner.drop") }

func (Outer* outer) drop() { println("Outer.drop") }

func main() int {

    o := Outer(Inner(box(1), box(2)), box(3))

    return 42

}

SRC



cat >"$work/partial_move_scope_exit.s" <<'SRC'

package fields

struct Left { data box }

struct Right { data box }

struct Pair { left Left; right Right }

func (Left* left) drop() { println("Left.drop") }

func (Right* right) drop() { println("Right.drop") }

func main() int {

    p := Pair(Left(box(1)), Right(box(2)))

    x := p.left

    return 42

}

SRC



cat >"$work/partial_move_arg.s" <<'SRC'

package fields

struct Left { data box }

struct Right { data box }

struct Pair { left Left; right Right }

func (Left* left) drop() { println("Left.drop") }

func (Right* right) drop() { println("Right.drop") }

func take(Left left) int { return 40 }

func main() int {

    p := Pair(Left(box(1)), Right(box(2)))

    return take(p.left) + 2

}

SRC

cat >"$work/quad_partial_move.s" <<'SRC'

package fields

struct Resource { data box }

struct Quad { a Resource; b Resource; c Resource; d Resource }

func (Resource* resource) drop() { println("drop-resource") }

func main() int {

    p := Quad(Resource(box(1)), Resource(box(2)), Resource(box(3)), Resource(box(4)))

    x := p.c

    return 42

}

SRC

cat >"$work/quad_field_borrow_then_move.s" <<'SRC'

package fields

struct Resource { data box }

struct Quad { a Resource; b Resource; c Resource; d Resource }

func (Resource* resource) drop() { println("drop-resource") }

func main() int {

    p := Quad(Resource(box(1)), Resource(box(2)), Resource(box(3)), Resource(box(4)))

    r := &p.c

    drop(r)

    x := p.c

    return 42

}

SRC



"$root/bin/s" "$work/ownership.s" -o "$work/ownership"

set +e

"$work/ownership"

status=$?

set -e

test "$status" -eq 42



"$root/bin/s" "$work/hello.s" -o "$work/hello"

test "$("$work/hello")" = "Hello, world!"



"$root/bin/s" "$work/string_helper.s" -o "$work/string_helper"

test "$("$work/string_helper")" = "Hello from helper"



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/struct_pair.s" -o "$work/struct_pair"

set +e

"$work/struct_pair"

status=$?

set -e

test "$status" -eq 42



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/early_return_cleanup.s" -o "$work/early_return_cleanup"

set +e

"$work/early_return_cleanup"

status=$?

set -e

test "$status" -eq 42



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/loop_cleanup.s" -o "$work/loop_cleanup"

set +e

"$work/loop_cleanup"

status=$?

set -e

test "$status" -eq 42



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/conditional_move_cleanup.s" -o "$work/conditional_move_cleanup"

set +e

"$work/conditional_move_cleanup"

status=$?

set -e

test "$status" -eq 42



"$root/bin/s_compiler" --emit-c "$work/drop_flag_elision.s" "$work/drop_flag_elision.c"

if grep -q 'compiler_drop(&s_v0)' "$work/drop_flag_elision.c" ||

   grep -q 'compiler_drop(&s_v1)' "$work/drop_flag_elision.c"; then

    echo "drop flag elision failed for moved owners" >&2

    cat "$work/drop_flag_elision.c" >&2

    exit 1

fi

if ! grep -q 'compiler_drop(&s_v2)' "$work/drop_flag_elision.c"; then

    echo "drop flag elision removed live owner cleanup" >&2

    cat "$work/drop_flag_elision.c" >&2

    exit 1

fi



cc -std=c11 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
    -fno-omit-frame-pointer -DS_COMPILER_CHECK_ALLOCATIONS \
    -I "$root/src/runtime" "$work/drop_flag_elision.c" -o "$work/drop_flag_elision"

set +e

"$work/drop_flag_elision"

status=$?

set -e

test "$status" -eq 42



run_custom_drop_case() {

    name=$1

    expected_output=$2

    S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/$name.s" -o "$work/$name"

    set +e

    output=$("$work/$name")

    status=$?

    set -e

    test "$status" -eq 42

    if [ "$output" != "$expected_output" ]; then

        echo "unexpected custom drop output for $name" >&2

        printf 'expected:\n%s\nactual:\n%s\n' "$expected_output" "$output" >&2

        exit 1

    fi

}



run_custom_drop_case custom_drop_scope_exit 'drop-resource'

run_custom_drop_case custom_drop_lifo "$(printf 'drop-b\ndrop-a')"

run_custom_drop_case custom_drop_move 'drop-moved'

run_custom_drop_case custom_drop_conditional_move 'drop-conditional'

run_custom_drop_case custom_drop_early_return 'drop-early'

run_custom_drop_case custom_drop_loop_break 'drop-break'

run_custom_drop_case custom_drop_loop_continue 'drop-continue'



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/overwrite_live_owner.s" -o "$work/overwrite_live_owner"

set +e

"$work/overwrite_live_owner"

status=$?

set -e

test "$status" -eq 42



run_custom_drop_case overwrite_custom_drop "$(printf 'drop-resource\ndrop-resource')"

run_custom_drop_case overwrite_moved_owner "$(printf 'drop-moved-reinit\ndrop-moved-reinit')"

run_custom_drop_case overwrite_conditional_true "$(printf 'drop-conditional-true\ndrop-conditional-true')"

run_custom_drop_case overwrite_conditional_false "$(printf 'drop-conditional-false\ndrop-conditional-false')"

run_custom_drop_case overwrite_inside_loop "$(printf 'drop-loop\ndrop-loop\ndrop-loop')"

run_custom_drop_case overwrite_early_return "$(printf 'drop-early-overwrite\ndrop-early-overwrite')"

run_custom_drop_case rhs_before_lhs_drop "$(printf 'make-rhs\ndrop-after-rhs\ndrop-after-rhs')"



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/struct_owned_fields_scope_exit.s" -o "$work/struct_owned_fields_scope_exit"

set +e

"$work/struct_owned_fields_scope_exit"

status=$?

set -e

test "$status" -eq 42



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/struct_owned_fields_early_return.s" -o "$work/struct_owned_fields_early_return"

set +e

"$work/struct_owned_fields_early_return"

status=$?

set -e

test "$status" -eq 42



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/struct_owned_fields_loop.s" -o "$work/struct_owned_fields_loop"

set +e

"$work/struct_owned_fields_loop"

status=$?

set -e

test "$status" -eq 42



run_custom_drop_case struct_custom_drop_with_fields 'Pair.drop'



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/general_struct_three_fields.s" -o "$work/general_struct_three_fields"

set +e

"$work/general_struct_three_fields"

status=$?

set -e

test "$status" -eq 42



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/mixed_struct_fields.s" -o "$work/mixed_struct_fields"

set +e

"$work/mixed_struct_fields"

status=$?

set -e

test "$status" -eq 42



S_COMPILER_CFLAGS=-DS_COMPILER_CHECK_ALLOCATIONS "$root/bin/s" "$work/nested_owned_struct.s" -o "$work/nested_owned_struct"

set +e

"$work/nested_owned_struct"

status=$?

set -e

test "$status" -eq 42



run_custom_drop_case nested_custom_drop_order "$(printf 'Outer.drop\nInner.drop')"

run_custom_drop_case partial_move_scope_exit "$(printf 'Left.drop\nRight.drop')"

run_custom_drop_case partial_move_arg "$(printf 'Left.drop\nRight.drop')"

run_custom_drop_case quad_partial_move "$(printf 'drop-resource\ndrop-resource\ndrop-resource\ndrop-resource')"

run_custom_drop_case quad_field_borrow_then_move "$(printf 'drop-resource\ndrop-resource\ndrop-resource\ndrop-resource')"



"$root/bin/s_compiler" --emit-c "$work/custom_drop_move.s" "$work/custom_drop_move.c"

if grep -q 'compiler_drop_user_Resource(s_v0)' "$work/custom_drop_move.c"; then

    echo "custom drop emitted for moved source owner" >&2

    cat "$work/custom_drop_move.c" >&2

    exit 1

fi

if ! grep -q 'compiler_drop_owned_Resource(&s_v1)' "$work/custom_drop_move.c"; then

    echo "custom drop missing for moved-to owner" >&2

    cat "$work/custom_drop_move.c" >&2

    exit 1

fi

"$root/bin/s_compiler" --emit-c "$work/custom_drop_conditional_move.s" "$work/custom_drop_conditional_move.c"

if ! grep -q 'compiler_drop_owned_Resource(&s_v0)' "$work/custom_drop_conditional_move.c" ||

   ! grep -q -F 'if (*owner)' "$work/custom_drop_conditional_move.c"; then

    echo "custom drop missing guarded owned cleanup" >&2

    cat "$work/custom_drop_conditional_move.c" >&2

    exit 1

fi



"$root/bin/s_compiler" --emit-c "$work/overwrite_custom_drop.s" "$work/overwrite_custom_drop.c"

rhs_line=$(grep -n 'compiler_new = compiler_make_Resource' "$work/overwrite_custom_drop.c" | head -1 | cut -d: -f1)

drop_line=$(grep -n 'compiler_drop_owned_Resource(&s_v0)' "$work/overwrite_custom_drop.c" | head -1 | cut -d: -f1)

assign_line=$(grep -n 's_v0 = compiler_new' "$work/overwrite_custom_drop.c" | head -1 | cut -d: -f1)

if [ -z "$rhs_line" ] || [ -z "$drop_line" ] || [ -z "$assign_line" ] ||

   [ "$rhs_line" -ge "$drop_line" ] || [ "$drop_line" -ge "$assign_line" ]; then

    echo "overwrite order is not RHS -> old drop -> assign" >&2

    cat "$work/overwrite_custom_drop.c" >&2

    exit 1

fi

"$root/bin/s_compiler" --emit-c "$work/overwrite_moved_owner.s" "$work/overwrite_moved_owner.c"

assign_reinit_line=$(grep -n 's_v0 = compiler_new' "$work/overwrite_moved_owner.c" | head -1 | cut -d: -f1)

old_reinit_drop_line=$(grep -n 'compiler_drop_owned_Resource(&s_v0)' "$work/overwrite_moved_owner.c" | head -1 | cut -d: -f1)

if [ -n "$old_reinit_drop_line" ] && [ "$old_reinit_drop_line" -lt "$assign_reinit_line" ]; then

    echo "moved LHS reinitialization dropped dead source" >&2

    cat "$work/overwrite_moved_owner.c" >&2

    exit 1

fi

"$root/bin/s_compiler" --emit-c "$work/overwrite_conditional_true.s" "$work/overwrite_conditional_true.c"

if ! grep -q 'compiler_drop_owned_Resource(&s_v0)' "$work/overwrite_conditional_true.c" ||

   ! grep -q -F 'if (*owner)' "$work/overwrite_conditional_true.c"; then

    echo "maybe-live overwrite missing guarded owned cleanup" >&2

    cat "$work/overwrite_conditional_true.c" >&2

    exit 1

fi



"$root/bin/s_compiler" --emit-c "$work/struct_custom_drop_with_fields.s" "$work/struct_custom_drop_with_fields.c"

if ! grep -q 'static void compiler_drop_user_Pair' "$work/struct_custom_drop_with_fields.c" ||

   ! grep -q 'compiler_drop_owned_Pair(&s_v0)' "$work/struct_custom_drop_with_fields.c"; then

    echo "custom drop with fields did not emit hook plus field cleanup" >&2

    cat "$work/struct_custom_drop_with_fields.c" >&2

    exit 1

fi

"$root/bin/s_compiler" --emit-c "$work/nested_owned_struct.s" "$work/nested_owned_struct.c"

if ! grep -q 'typedef struct S_Outer' "$work/nested_owned_struct.c" ||

   ! grep -q -F 'S_Inner *inner' "$work/nested_owned_struct.c" ||

   ! grep -q 'compiler_drop_owned_Inner(&value->inner)' "$work/nested_owned_struct.c"; then

    echo "recursive named struct cleanup was not generated" >&2

    cat "$work/nested_owned_struct.c" >&2

    exit 1

fi

tail_line=$(grep -n -F 'compiler_drop(&value->tail)' "$work/nested_owned_struct.c" | head -1 | cut -d: -f1)

inner_line=$(grep -n -F 'compiler_drop_owned_Inner(&value->inner)' "$work/nested_owned_struct.c" | head -1 | cut -d: -f1)

if [ -z "$tail_line" ] || [ -z "$inner_line" ] || [ "$tail_line" -ge "$inner_line" ]; then

    echo "nested field cleanup is not reverse declaration order" >&2

    cat "$work/nested_owned_struct.c" >&2

    exit 1

fi

"$root/bin/s_compiler" --emit-c "$work/mixed_struct_fields.s" "$work/mixed_struct_fields.c"

if grep -q 'compiler_drop(&value->id)' "$work/mixed_struct_fields.c" ||

   grep -q 'compiler_drop(&value->active)' "$work/mixed_struct_fields.c" ||

   ! grep -q 'compiler_drop(&value->data)' "$work/mixed_struct_fields.c"; then

    echo "mixed field cleanup did not isolate owned fields" >&2

    cat "$work/mixed_struct_fields.c" >&2

    exit 1

fi

"$root/bin/s_compiler" --emit-c "$work/partial_move_scope_exit.s" "$work/partial_move_scope_exit.c"

if ! grep -q 'compiler_move_Left(&s_v0->left)' "$work/partial_move_scope_exit.c" ||

   ! grep -q 'compiler_drop_owned_Right(&value->right)' "$work/partial_move_scope_exit.c" ||

   ! grep -q 'compiler_drop_owned_Left(&value->left)' "$work/partial_move_scope_exit.c"; then

    echo "partial move generated C did not move field and preserve guarded field cleanup" >&2

    cat "$work/partial_move_scope_exit.c" >&2

    exit 1

fi

"$root/bin/s_compiler" --emit-c "$work/quad_partial_move.s" "$work/quad_partial_move.c"

if ! grep -q 'compiler_move_Resource(&s_v0->c)' "$work/quad_partial_move.c" ||
   grep -q '__field_p_c' "$work/quad_partial_move.c" ||
   grep -q '__field_s_v0_c' "$work/quad_partial_move.c"; then

    echo "quad partial move did not use the real aggregate field" >&2

    cat "$work/quad_partial_move.c" >&2

    exit 1

fi



if nm "$work/hello" "$work/ownership" "$work/string_helper" "$work/struct_pair" "$work/early_return_cleanup" "$work/loop_cleanup" "$work/conditional_move_cleanup" "$work/drop_flag_elision" "$work/custom_drop_scope_exit" "$work/custom_drop_lifo" "$work/custom_drop_move" "$work/custom_drop_conditional_move" "$work/custom_drop_early_return" "$work/custom_drop_loop_break" "$work/custom_drop_loop_continue" "$work/overwrite_live_owner" "$work/overwrite_custom_drop" "$work/overwrite_moved_owner" "$work/overwrite_conditional_true" "$work/overwrite_conditional_false" "$work/overwrite_inside_loop" "$work/overwrite_early_return" "$work/rhs_before_lhs_drop" "$work/struct_owned_fields_scope_exit" "$work/struct_owned_fields_early_return" "$work/struct_owned_fields_loop" "$work/struct_custom_drop_with_fields" "$work/general_struct_three_fields" "$work/mixed_struct_fields" "$work/nested_owned_struct" "$work/nested_custom_drop_order" "$work/partial_move_scope_exit" "$work/partial_move_arg" "$work/quad_partial_move" "$work/quad_field_borrow_then_move" | grep -E 'runtime_gc|run_gc|mark_roots|sweep_pass|runtime_execute|SSEED|gc_' >/dev/null; then

    echo "GC or seed runtime symbol linked into no-GC binary" >&2

    exit 1

fi



if "$root/bin/s" "$work/reject.s" -o "$work/reject" >/dev/null 2>&1; then

    echo "borrow violation unexpectedly compiled" >&2

    exit 1

fi



check_diagnostic() {

    name=$1

    source=$2

    printf '%s\n' "$source" >"$work/$name.s"

    if "$root/bin/s" "$work/$name.s" -o "$work/$name" >"$work/$name.out" 2>&1; then

        echo "unsupported syntax unexpectedly compiled: $name" >&2

        exit 1

    fi

    if ! grep -q 'unsupported in no-GC compiler subset' "$work/$name.out"; then

        echo "missing no-GC subset diagnostic for $name" >&2

        cat "$work/$name.out" >&2

        exit 1

    fi

}



check_diagnostic import 'package bad

use std.io.println

func main() int { return 0 }'



check_diagnostic enum 'package bad

enum option { some none }

func main() int { return 0 }'



check_diagnostic struct_shape 'package bad

struct pair { value box }

func main() int { return 0 }'



cat >"$work/struct_mismatch.s" <<'SRC'

package bad

struct Pair { first box; second box }

struct Duo { left box; right box }

func sum(Pair p) int { return *p.first + *p.second }

func main() int {

    d := Duo(box(1), box(2))

    return sum(d)

}

SRC

if "$root/bin/s" "$work/struct_mismatch.s" -o "$work/struct_mismatch" >"$work/struct_mismatch.out" 2>&1; then

    echo "struct type mismatch unexpectedly compiled" >&2

    exit 1

fi

if ! grep -q 'function argument struct type mismatch' "$work/struct_mismatch.out"; then

    echo "missing struct mismatch diagnostic" >&2

    cat "$work/struct_mismatch.out" >&2

    exit 1

fi



expect_compile_fail() {

    name=$1

    source=$2

    needle=$3

    printf '%s\n' "$source" >"$work/$name.s"

    if "$root/bin/s" "$work/$name.s" -o "$work/$name" >"$work/$name.out" 2>&1; then

        echo "invalid program unexpectedly compiled: $name" >&2

        exit 1

    fi

    if ! grep -q "$needle" "$work/$name.out"; then

        echo "missing expected diagnostic for $name" >&2

        cat "$work/$name.out" >&2

        exit 1

    fi

}



expect_compile_fail invalid_drop_args 'package bad

struct File { first box; second box }

func (File* f) drop(int code) { }

func main() int { value := File(box(1), box(2)); return 42 }' 'drop method must not have parameters'



expect_compile_fail invalid_drop_return 'package bad

struct File { first box; second box }

func (File* f) drop() int { return 0 }

func main() int { value := File(box(1), box(2)); return 42 }' 'drop method must not return a value'



expect_compile_fail duplicate_drop 'package bad

struct File { first box; second box }

func (File* f) drop() { }

func (File* g) drop() { }

func main() int { value := File(box(1), box(2)); return 42 }' 'duplicate drop method'



expect_compile_fail self_assignment 'package bad

struct File { first box; second box }

func (File* f) drop() { println("drop") }

func main() int {

    value := File(box(1), box(2))

    value = value

    return 42

}' 'self move is not supported'



expect_compile_fail partial_move_use_after_move 'package bad

struct Left { data box }

struct Right { data box }

struct Pair { left Left; right Right }

func main() int {

    p := Pair(Left(box(1)), Right(box(2)))

    x := p.left

    y := p.left

    return 42

}' 'use of moved owned struct field'

expect_compile_fail partial_move_arg_after_move 'package bad

struct Resource { data box }

struct Quad { a Resource; b Resource; c Resource; d Resource }

func use(Resource resource) int { return 1 }

func main() int {

    p := Quad(Resource(box(1)), Resource(box(2)), Resource(box(3)), Resource(box(4)))

    x := p.c

    return use(p.c)

}' 'use of moved owned struct field'

expect_compile_fail partial_move_whole_move 'package bad

struct Resource { data box }

struct Quad { a Resource; b Resource; c Resource; d Resource }

func main() int {

    p := Quad(Resource(box(1)), Resource(box(2)), Resource(box(3)), Resource(box(4)))

    x := p.c

    q := p

    return 42

}' 'cannot move partially moved struct'

expect_compile_fail partial_move_borrow_conflict 'package bad

struct Resource { data box }

struct Quad { a Resource; b Resource; c Resource; d Resource }

func main() int {

    p := Quad(Resource(box(1)), Resource(box(2)), Resource(box(3)), Resource(box(4)))

    r := &p.c

    x := p.c

    return 42

}' 'cannot move borrowed pair field'

expect_compile_fail cfg_field_maybe_moved_read 'package bad

struct Resource { data box }

struct Quad { a Resource; b Resource; c Resource; d Resource }

func use(Resource resource) int { return 1 }

func main() int {

    p := Quad(Resource(box(1)), Resource(box(2)), Resource(box(3)), Resource(box(4)))

    if true {

        x := p.c

    }

    return use(p.c)

}' 'use of conditionally moved owned struct field'

expect_compile_fail cfg_field_maybe_moved_move 'package bad

struct Resource { data box }

struct Quad { a Resource; b Resource; c Resource; d Resource }

func main() int {

    p := Quad(Resource(box(1)), Resource(box(2)), Resource(box(3)), Resource(box(4)))

    if true {

        x := p.c

    }

    y := p.c

    return 42

}' 'use of conditionally moved owned struct field'

expect_compile_fail cfg_field_moved_both_branches 'package bad

struct Resource { data box }

struct Quad { a Resource; b Resource; c Resource; d Resource }

func main() int {

    p := Quad(Resource(box(1)), Resource(box(2)), Resource(box(3)), Resource(box(4)))

    if true {

        x := p.c

    } else {

        y := p.c

    }

    z := p.c

    return 42

}' 'use of moved owned struct field'



echo "No-GC compiler checks passed"
