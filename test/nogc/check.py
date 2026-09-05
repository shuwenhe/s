#!/usr/bin/env python3
"""Compile real S sources, execute generated code, and reject unsafe programs."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
COMPILER = ROOT / "bin/s_nogc_compiler"
CC = os.environ.get("CC", "cc")


def run(args, expected=0):
    p = subprocess.run([str(x) for x in args], capture_output=True, text=True, timeout=60)
    if p.returncode != expected:
        raise AssertionError(f"{args}\nexit={p.returncode}, expected={expected}\n{p.stdout}{p.stderr}")
    return p


def source(body):
    return "package test\nfunc main() int {\n" + body + "\n}\n"


POSITIVE = {
    "reborrow_continue": ("a := box(0); r := &mut a; while *r < 42 { t := &mut *r; *t = *t + 1; continue; } return *r;", 42),
    "reborrow_break": ("a := box(1); r := &mut a; while true { t := &mut *r; *t = 42; break; } return *r;", 42),
    "reborrow_return_branch": ("a := box(42); r := &mut a; t := &mut *r; if false { return *t; } else { drop(t); } return *r;", 42),
    "copied_reborrow_release": ("a := box(1); r := &mut a; t := &*r; u := t; drop(t); drop(u); *r = 42; return *r;", 42),
    "reborrow_slot_reuse": ("a := box(42); r := &mut a; { t := &mut *r; assert(*t == 42); } x := 0; *r = 42 + x; return *r;", 42),
    "shared_copy": ("a := box(42); r := &a; t := r; drop(r); assert(*t == 42); drop(t); b := a; return *b;", 42),
    "shared_reborrow": ("a := box(42); r := &a; { t := &*r; assert(*t == 42); } return *r;", 42),
    "mutable_reborrow": ("a := box(20); r := &mut a; { t := &mut *r; *t = *t + 22; } return *r;", 42),
    "shared_from_mutable": ("a := box(42); r := &mut a; { t := &*r; u := t; assert(*r + *u == 84); drop(t); assert(*u == 42); } *r = 42; return *r;", 42),
    "nested_reborrow": ("a := box(1); r := &mut a; { t := &mut *r; { u := &mut *t; *u = 42; } assert(*t == 42); } return *r;", 42),
    "explicit_reborrow_end": ("a := box(1); r := &mut a; t := &mut *r; *t = 42; drop(t); return *r;", 42),
    "loop_reborrow": ("a := box(0); r := &mut a; while *r < 42 { t := &mut *r; *t = *t + 1; } return *r;", 42),
    "branch_reborrow_end": ("a := box(42); r := &mut a; t := &mut *r; if true { drop(t); } else { drop(t); } return *r;", 42),
    "unused": ("x := 1; x = 2; a := box(7); r := &a; return 42;", 42),
    "move": ("a := box(42); b := a; return *b;", 42),
    "scope": ("{ a := box(7); assert(live_allocations() == 1); } assert(live_allocations() == 0); return 42;", 42),
    "borrow": ("a := box(42); r := &a; t := &a; return *r + *t - 42;", 42),
    "mutable": ("a := box(20); { r := &mut a; *r = *r + 22; } return *a;", 42),
    "end_borrow": ("a := box(42); r := &a; drop(r); b := a; return *b;", 42),
    "overwrite": ("a := box(20); a = box(*a + 22); assert(live_allocations() == 1); return *a;", 42),
    "move_overwrite": ("a := box(1); b := box(42); a = b; assert(live_allocations() == 1); return *a;", 42),
    "reinitialize": ("a := box(1); b := a; a = box(41); return *a + *b;", 42),
    "conditional_drop": ("a := box(42); if true { drop(a); } assert(live_allocations() == 0); return 42;", 42),
    "conditional_live": ("a := box(42); if false { drop(a); } assert(live_allocations() == 1); return 42;", 42),
    "conditional_reset": ("a := box(1); if true { drop(a); } a = box(42); return *a;", 42),
    "early_return": ("a := box(42); if true { b := a; return *b; } return *a;", 42),
    "both_return": ("a := box(42); if false { return *a; } else { b := a; return *b; }", 42),
    "loop": ("i := 0; while i < 100 { a := box(i); i = *a + 1; } assert(live_allocations() == 0); return 42;", 42),
    "continue": ("i := 0; while i < 5 { a := box(i); i = *a + 1; continue; } assert(live_allocations() == 0); return 42;", 42),
    "break": ("a := box(42); while true { b := box(7); { c := box(8); break; } } assert(live_allocations() == 1); return *a;", 42),
    "nested_break": ("while true { a := box(42); while true { b := box(1); break; } assert(live_allocations() == 1); return *a; } return 0;", 42),
    "branch_continue": ("i := 0; while i < 4 { a := box(i); i = i + 1; if i < 4 { continue; } assert(*a == 3); } return 42;", 42),
    "fallthrough": ("a := box(42);", 0),
    "comments": ("/* &mut /* nested */ drop(a) */ a := box(00042); // use extern\nreturn *a;", 42),
    "precedence": ("return 2 + 5 * 8;", 42),
    "short_circuit": ("assert(true || 1 / 0); assert(!(false && 1 / 0)); return 42;", 42),
}
NEGATIVE = {
    "reborrow_keeps_root_borrowed": ("a := box(1); r := &mut a; t := &mut *r; drop(a);", "borrowed"),
    "shared_during_mutable_reborrow": ("a := box(1); r := &mut a; t := &mut *r; u := &*r;", "reborrow"),
    "drop_shared_parent": ("a := box(1); r := &a; t := &*r; drop(r);", "reborrow"),
    "copy_dropped_shared": ("a := box(1); r := &a; drop(r); t := r;", "dropped"),
    "reborrow_dropped_reference": ("a := box(1); r := &mut a; drop(r); t := &mut *r;", "dropped"),
    "copied_shared_cannot_mutate": ("a := box(1); r := &mut a; t := &*r; u := t; v := &mut *u;", "shared reference"),
    "copy_keeps_owner_borrowed": ("a := box(1); r := &a; t := r; drop(r); drop(a);", "borrowed"),
    "read_suspended_parent": ("a := box(1); r := &mut a; t := &mut *r; return *r;", "reborrow"),
    "write_suspended_parent": ("a := box(1); r := &mut a; t := &*r; *r = 2;", "reborrow"),
    "drop_suspended_parent": ("a := box(1); r := &mut a; t := &mut *r; drop(r);", "reborrow"),
    "mutable_from_shared": ("a := box(1); r := &a; t := &mut *r;", "shared reference"),
    "conflicting_reborrows": ("a := box(1); r := &mut a; t := &*r; u := &mut *r;", "reborrow"),
    "copy_keeps_parent_borrowed": ("a := box(1); r := &mut a; t := &*r; u := t; drop(t); *r = 2;", "reborrow"),
    "grandchild_freezes_parent": ("a := box(1); r := &mut a; t := &mut *r; u := &*t; return *r;", "reborrow"),
    "branch_reborrow_live": ("a := box(1); r := &mut a; t := &mut *r; if true { drop(t); } return *r;", "reborrow"),
    "reborrow_scalar": ("a := 1; r := &*a;", "reference"),
    "use_after_move": ("a := box(1); b := a; return *a;", "moved"),
    "double_drop": ("a := box(1); drop(a); drop(a);", "dropped"),
    "move_borrowed": ("a := box(1); r := &a; b := a;", "borrowed"),
    "drop_borrowed": ("a := box(1); r := &a; drop(a);", "borrowed"),
    "overwrite_borrowed": ("a := box(1); r := &a; a = box(2);", "borrowed"),
    "two_mutable": ("a := box(1); r := &mut a; t := &mut a;", "conflicting"),
    "shared_then_mutable": ("a := box(1); r := &a; t := &mut a;", "conflicting"),
    "mutable_then_shared": ("a := box(1); r := &mut a; t := &a;", "conflicting"),
    "read_mutably_borrowed": ("a := box(1); r := &mut a; return *a;", "mutable borrow"),
    "write_borrowed_owner": ("a := box(1); r := &a; *a = 3;", "borrowed"),
    "write_shared": ("a := box(1); r := &a; *r = 3;", "mutable reference"),
    "return_reference": ("a := box(1); return &a;", "cannot escape"),
    "return_owner": ("a := box(1); return a;", "cannot escape"),
    "scope_escape": ("{ a := box(1); } return *a;", "unknown"),
    "branch_move": ("a := box(1); if true { b := a; } return *a;", "conditionally"),
    "branch_drop_ref": ("a := box(1); r := &a; if true { drop(r); } b := a;", "borrowed"),
    "branch_ref_use": ("a := box(1); r := &a; if true { drop(r); } return *r;", "conditionally"),
    "loop_move": ("a := box(1); while true { b := a; break; }", "outer owner"),
    "nested_loop_move": ("while true { a := box(1); while true { b := a; } }", "outer owner"),
    "loop_drop_reference": ("a := box(1); r := &a; while true { drop(r); }", "outer borrow"),
    "reference_copy": ("a := box(1); r := &mut a; t := r;", "reference copying"),
    "reference_assignment": ("a := box(1); b := box(2); r := &a; r = &b;", "reassignment"),
    "self_move": ("a := box(1); a = a;", "self move"),
    "unknown_call": ("gc_collect();", "unsupported statement"),
    "raw_pointer": ("a := malloc(8);", "unknown variable"),
    "bad_literal": ("return 42xyz;", "invalid decimal"),
    "large_literal": ("return 9223372036854775808;", "18 decimal"),
    "missing_semicolon": ("a := box(1) return 42;", "expected ';'"),
    "unclosed_comment": ("/*", "unterminated comment"),
    "illegal_token": ("return @;", "unsupported token"),
    "break_outside": ("break;", "outside a loop"),
    "unreachable": ("return 42; a := box(1);", "unreachable"),
    "both_return_unreachable": ("if true { return 1; } else { return 2; } a := box(3);", "unreachable"),
    "nested_limit": ("{" * 65 + "}" * 65, "nesting limit"),
}


def main():
    with tempfile.TemporaryDirectory(prefix="s-nogc-tests-") as td:
        work = Path(td)
        for name, (body, expected) in POSITIVE.items():
            src, c, exe = (work / (name + suffix) for suffix in (".s", ".c", ".bin"))
            src.write_text(source(body))
            run([COMPILER, "--emit-c", src, c])
            run([CC, "-std=c11", "-O1", "-g", "-Wall", "-Wextra", "-Werror", 
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-DS_NOGC_CHECK_ALLOCATIONS",
                 "-I", ROOT / "src/runtime", c, "-o", exe])
            run([exe], expected)
            print("PASS", name, flush=True)
        for name, (body, diagnostic) in NEGATIVE.items():
            src, c = work / (name + ".s"), work / (name + ".c")
            src.write_text(source(body))
            # Rejection must preserve an existing artifact, not write partial C.
            c.write_text("sentinel")
            result = run([COMPILER, "--emit-c", src, c], 1)
            assert diagnostic in result.stderr, (name, result.stderr)
            assert c.read_text() == "sentinel", name
            print("PASS reject", name, flush=True)
        for name, body in {"divide_zero": "return 1 / 0;", "overflow": "return 999999999999999999 * 999999999999999999;"}.items():
            src, c, exe = (work / (name + suffix) for suffix in (".s", ".c", ".bin"))
            src.write_text(source(body))
            run([COMPILER, "--emit-c", src, c])
            run([CC, "-std=c11", "-I", ROOT / "src/runtime", c, "-o", exe])
            run([exe], 70)
        # Exercise the public driver and inspect the linked application.
        exe = work / "ownership"
        run([ROOT / "misc/scripts/s-nogc.sh", "build", ROOT / "test/nogc/ownership.s", "-o", exe])
        run([exe], 42)
        symbols = run(["nm", exe]).stdout
        for forbidden in ("runtime_gc", "run_gc", "mark_roots", "sweep_pass", "runtime_execute"):
            assert forbidden not in symbols, forbidden
    print(f"No-GC checks passed: {len(POSITIVE)} execution, {len(NEGATIVE)} rejection, 2 runtime traps, driver and symbols")


if __name__ == "__main__":
    main()
