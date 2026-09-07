"""Regression checks for call-duration loans and parameter cleanup."""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES = [
    ("return_ref", "func identity(ref a) ref { return a; }",
     "a := box(42); r := identity(&a); return *r;", True),
    ("return_mutref", "func identity(mutref a) mutref { return a; }",
     "a := box(1); r := identity(&mut a); *r = 42; return *r;", True),
    ("return_second_ref", "func second(int x, ref a) ref { return a; }",
     "a := box(42); r := second(0, &a); return *r;", True),
    ("return_second_mutref", "func second(int x, mutref a) mutref { return a; }",
     "a := box(1); r := second(0, &mut a); *r = 42; return *r;", True),
    ("return_ref_mismatch", "func bad(ref a, ref b) ref { if true { return a; } else { return b; } }",
     "a := box(1); b := box(2); r := bad(&a, &b); return *r;", False),
    ("return_local_ref", "func bad(box a) ref { r := &a; return r; }",
     "a := box(42); r := bad(a); return *r;", False),
    ("return_ref_missing", "func bad(ref a) ref { if true { return a; } }",
     "a := box(42); r := bad(&a); return *r;", False),
    ("loop_evaluation", "func bump(mutref a) int { *a = *a + 1; return *a; }",
     "a := box(0); while bump(&mut a) < 42 { } return *a;", True),
    ("mutation_order", "func bump(mutref a) int { *a = *a + 1; return *a; }",
     "a := box(20); return *a + bump(&mut a) + 1;", True),
    ("operand_order", "func take(box a) int { return *a; }",
     "a := box(21); return *a + take(a);", True),
    ("argument_order", "func take(box a) int { return *a; } func add(int a, int b) int { return a + b; }",
     "a := box(21); return add(*a, take(a));", True),
    ("fresh_argument", "func take(box a) int { return *a; }",
     "return take(box(42));", True),
    ("nested_owner", "func make() box { return box(42); } func take(box a) int { return *a; }",
     "return take(make());", True),
    ("short_circuit_cleanup", "func take(box a) int { return *a; }",
     "a := box(42); x := false && take(a); assert(live_allocations() == 1); return 42;", True),
    ("short_circuit_move", "func take(box a) int { return *a; }",
     "a := box(42); x := false && take(a); return *a;", False),
    ("condition_move", "func take(box a) int { return *a; }",
     "a := box(42); while take(a) { } return 42;", False),
    ("write_consumed", "func take(box a) int { return *a; }",
     "a := box(42); *a = take(a); return 42;", False),
    ("return_new", "func f() box { return box(42); }",
     "a := f(); return *a;", True),
    ("return_move", "func f(box a) box { unused := box(7); return a; }",
     "a := box(42); b := f(a); assert(live_allocations() == 1); return *b;", True),
    ("return_borrowed", "func f(box a) box { r := &a; return a; }",
     "a := box(42); b := f(a); return *b;", False),
    ("return_missing", "func f() box { if true { return box(42); } }",
     "a := f(); return *a;", False),
    ("return_branches", "func f(int x) box { if x { return box(42); } else { return box(1); } }",
     "a := f(1); return *a;", True),
    ("alias", "func f(mutref a, ref b) int { return *a + *b; }",
     "a := box(1); return f(&mut a, &a);", False),
    ("move_borrowed", "func f(ref a, box b) int { return *a + *b; }",
     "a := box(1); return f(&a, a);", False),
    ("shared", "func f(ref a, ref b) int { return *a + *b; }",
     "a := box(21); return f(&a, &a);", True),
    ("fallthrough", "func f(box a) int { assert(*a == 42); }",
     "a := box(42); x := f(a); assert(live_allocations() == 0); return 42;", True),
]

with tempfile.TemporaryDirectory(prefix="s-call-regression-") as directory:
    work = Path(directory)
    for name, helper, body, accepted in CASES:
        source, output, executable = (work / (name + suffix) for suffix in (".s", ".c", ".bin"))
        source.write_text("package test\n" + helper + "\nfunc main() int { " + body + " }\n")
        output.write_text("sentinel")
        result = subprocess.run([ROOT / "bin/s_compiler", "--emit-c", source, output],
                                capture_output=True, text=True, timeout=30)
        if not accepted:
            assert result.returncode == 1, (name, result.stderr)
            assert output.read_text() == "sentinel", name
        else:
            assert result.returncode == 0, (name, result.stderr)
            subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror",
                            "-DS_COMPILER_CHECK_ALLOCATIONS", "-I", ROOT / "src/runtime",
                            output, "-o", executable], check=True, timeout=30)
            assert subprocess.run([executable], timeout=30).returncode == 42, name
        print("PASS", name)
