"""Regression checks for call-duration loans and parameter cleanup."""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES = [
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
