package test.compiler

use std.fs.make_temp_dir
use std.fs.write_text_file
use std.io.eprintln
use std.process.run_process
use std.process.run_process_output

func source(string helper, string body) string {
    "package test\n" + helper + "\nfunc main() int {\n" + body + "\n}\n"
}

func run_expected(string[] argv) int {
    command := ""
    i := 0
    while i < len(argv) {
        if i > 0 { command = command + " " }
        command = command + argv[i]
        i = i + 1
    }
    command = command + "; status=$?; test $status -eq 42"
    result := run_process(["sh", "-c", command])
    if result.is_err() {
        eprintln("unexpected process status")
        return 1
    }
    0
}

func run_case(string dir, string compiler, string cc, string name,
             string helper, string body, bool accepted) int {
    source_path := dir + "/" + name + ".s"
    c_path := dir + "/" + name + ".c"
    exe_path := dir + "/" + name + ".bin"
    if write_text_file(source_path, source(helper, body)).is_err() { return 1 }
    if write_text_file(c_path, "sentinel").is_err() { return 1 }

    result := run_process_output([compiler, "--emit-c", source_path, c_path])
    if !accepted {
        if result.is_ok() { eprintln("accepted rejected case: " + name); return 1 }
        eprintln("PASS reject " + name)
        return 0
    }
    if result.is_err() { eprintln("rejected accepted case: " + name); return 1 }
    cc_result := run_process([cc, "-std=c11", "-O1", "-Wall", "-Wextra", "-Werror",
        "-DS_COMPILER_CHECK_ALLOCATIONS", "-I", "src/runtime", c_path, "-o", exe_path])
    if cc_result.is_err() { eprintln("C compilation failed: " + name); return 1 }
    if run_expected([exe_path]) != 0 { return 1 }
    eprintln("PASS " + name)
    0
}

func main() int {
    temp := make_temp_dir("s-call-regression-")
    if temp.is_err() { eprintln("cannot create temporary directory"); return 1 }
    dir := temp.unwrap()
    compiler := "./bin/s_compiler"
    cc := "cc"

    if run_case(dir, compiler, cc, "return_ref",
        "func identity(ref a) ref { return a; }",
        "a := box(42); r := identity(&a); return *r;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "return_second_ref",
        "func second(int x, ref a) ref { return a; }",
        "a := box(42); r := second(0, &a); return *r;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "return_mutref",
        "func identity(mutref a) mutref { return a; }",
        "a := box(1); r := identity(&mut a); *r = 42; return *r;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "return_box",
        "func identity(box a) box { return a; }",
        "a := box(42); b := identity(a); return *b;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "shared_arguments",
        "func add(ref a, ref b) int { return *a + *b; }",
        "a := box(21); return add(&a, &a);", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "mutation_order",
        "func bump(mutref a) int { *a = *a + 1; return *a; }",
        "a := box(20); return *a + bump(&mut a) + 1;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "short_circuit_cleanup",
        "func consume(box a) int { return *a; }",
        "a := box(42); x := false && consume(a); assert(live_allocations() == 1); return 42;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "integer_array",
        "",
        "values := [20, 22]; assert(len(values) == 2); values[1] = 23; return values[0] + values[1] - 1;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "mutable_array_parameter",
        "func bump(mutint[] values) int { values[0] = values[0] + 1; return values[0]; }",
        "values := [20]; assert(bump(values) == 21); return values[0] + 21;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "pair_fields",
        "",
        "p := pair(box(20), box(22)); return *p.left + *p.right;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "pair_field_move",
        "",
        "p := pair(box(20), box(22)); left := p.left; return *left + *p.right;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "pair_return",
        "func forward(pair p) pair { return p; }",
        "p := forward(pair(box(20), box(22))); return *p.left + *p.right;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "pair_parameter",
        "func sum(pair p) int { return *p.left + *p.right; }",
        "p := pair(box(20), box(22)); return sum(p);", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "pair_field_borrow",
        "",
        "p := pair(box(20), box(22)); *p.right = 23; r := &p.left; return *r + *p.right;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "pair_field_mutborrow",
        "",
        "p := pair(box(20), box(22)); r := &mut p.left; *r = 21; return *r;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "pair_field_mutborrow_conflict",
        "",
        "p := pair(box(20), box(22)); r := &mut p.left; *p.right = 21; return *r;", false) != 0 { return 1 }
    if run_case(dir, compiler, cc, "pair_scope_drop",
        "",
        "{ p := pair(box(20), box(22)); assert(live_allocations() == 3); } assert(live_allocations() == 0); return 42;", true) != 0 { return 1 }
    if run_case(dir, compiler, cc, "pair_double_field_move",
        "",
        "p := pair(box(20), box(22)); left := p.left; second := p.left; return *left;", false) != 0 { return 1 }
    if run_case(dir, compiler, cc, "return_local_ref",
        "func bad(box a) ref { r := &a; return r; }",
        "a := box(42); r := bad(a); return *r;", false) != 0 { return 1 }
    if run_case(dir, compiler, cc, "return_ref_mismatch",
        "func bad(ref a, ref b) ref { if true { return a; } else { return b; } }",
        "a := box(1); b := box(2); r := bad(&a, &b); return *r;", false) != 0 { return 1 }
    if run_case(dir, compiler, cc, "move_borrowed",
        "func bad(ref a, box b) int { return *a + *b; }",
        "a := box(1); return bad(&a, a);", false) != 0 { return 1 }
    if run_case(dir, compiler, cc, "condition_move",
        "func consume(box a) int { return *a; }",
        "a := box(42); while consume(a) { } return 42;", false) != 0 { return 1 }
    if run_case(dir, compiler, cc, "fallthrough_box",
        "func bad() box { if true { return box(42); } }",
        "a := bad(); return *a;", false) != 0 { return 1 }

    eprintln("S call regressions passed")
    0
}
