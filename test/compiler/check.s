package test.compiler

use std.fs.make_temp_dir
use std.fs.write_text_file
use std.io.eprintln
use std.io.println
use std.process.run_process
use std.process.run_process_output

func source(string body) string {
    "package test\nfunc main() int {\n" + body + "\n}\n"
}

func write_fixture(string dir, string name, string body) string {
    path := dir + "/" + name + ".s"
    result := write_text_file(path, source(body))
    if result.is_err() {
        eprintln("cannot write fixture: " + path)
        return ""
    }
    path
}

func run_checked(string[] argv) int {
    result := run_process(argv)
    if result.is_err() {
        eprintln("command failed: " + result.unwrap_err().message)
        return 1
    }
    0
}

func run_expected(string[] argv, int expected) int {
    command := ""
    for i := 0; i < len(argv); i = i + 1 {
        if i > 0 { command = command + " " }
        command = command + argv[i]
    }
    command = command + "; status=$?; test $status -eq " + int_to_string(expected)
    result := run_process(["sh", "-c", command])
    if result.is_err() {
        eprintln("unexpected process status: " + result.unwrap_err().message)
        return 1
    }
    0
}

func int_to_string(int value) string {
    if value == 0 { return "0" }
    if value == 42 { return "42" }
    if value == 70 { return "70" }
    "1"
}

func compile_to_c(string compiler, string source_path, string c_path) int {
    run_checked([compiler, "--emit-c", source_path, c_path])
}

func compile_and_run(string dir, string compiler, string cc, string name, string body, int expected) int {
    source_path := write_fixture(dir, name, body)
    if source_path == "" { return 1 }
    c_path := dir + "/" + name + ".c"
    exe_path := dir + "/" + name + ".bin"
    if compile_to_c(compiler, source_path, c_path) != 0 { return 1 }
    if run_checked([cc, "-std=c11", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
        "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
        "-DS_COMPILER_CHECK_ALLOCATIONS", "-I", "src/runtime", c_path, "-o", exe_path]) != 0 {
        return 1
    }
    run_expected([exe_path], expected)
}

func reject(string dir, string compiler, string name, string body) int {
    source_path := write_fixture(dir, name, body)
    if source_path == "" { return 1 }
    c_path := dir + "/" + name + ".c"
    result := write_text_file(c_path, "sentinel")
    if result.is_err() { return 1 }
    compile_result := run_process_output([compiler, "--emit-c", source_path, c_path])
    if compile_result.is_ok() {
        eprintln("rejected fixture compiled: " + name)
        return 1
    }
    0
}

func symbol_check(string dir, string compiler) int {
    source_path := write_fixture(dir, "ownership", "a := box(42); r := &a; return *r;")
    if source_path == "" { return 1 }
    exe_path := dir + "/ownership.bin"
    build_result := run_process(["misc/scripts/s-compiler.sh", "build", source_path, "-o", exe_path])
    if build_result.is_err() { return 1 }
    if run_expected([exe_path], 42) != 0 { return 1 }
    symbols := run_process_output(["nm", exe_path])
    if symbols.is_err() { return 1 }
    text := symbols.unwrap()
    if contains(text, "runtime_gc") || contains(text, "run_gc") || contains(text, "mark_roots") ||
        contains(text, "sweep_pass") || contains(text, "runtime_execute") {
        eprintln("GC symbol linked into ownership binary")
        return 1
    }
    0
}

func contains(string text, string needle) bool {
    if needle == "" { return true }
    if len(needle) > len(text) { return false }
    for i := 0; i <= len(text) - len(needle); i = i + 1 {
        matched := true
        for j := 0; j < len(needle); j = j + 1 {
            if char_at(text, i + j) != char_at(needle, j) {
                matched = false
                break
            }
        }
        if matched { return true }
    }
    false
}

func char_at(string text, int index) string {
    __host_char_at(text, index)
}

extern "intrinsic" func __host_char_at(string text, int index) string;

func main() int {
    temp_result := make_temp_dir("s-compiler-check-")
    if temp_result.is_err() {
        eprintln("cannot create test directory")
        return 1
    }
    dir := temp_result.unwrap()
    compiler := "./bin/s_compiler"
    cc := "cc"

    if compile_and_run(dir, compiler, cc, "reborrow", "a := box(0); r := &mut a; while *r < 42 { t := &mut *r; *t = *t + 1; } return *r;", 42) != 0 { return 1 }
    if compile_and_run(dir, compiler, cc, "scope", "{ a := box(7); assert(live_allocations() == 1); } assert(live_allocations() == 0); return 42;", 42) != 0 { return 1 }
    if compile_and_run(dir, compiler, cc, "divide_zero", "return 1 / 0;", 70) != 0 { return 1 }
    if reject(dir, compiler, "borrow_error", "a := box(1); r := &a; drop(a);") != 0 { return 1 }
    if reject(dir, compiler, "syntax_error", "return @;") != 0 { return 1 }
    if symbol_check(dir, compiler) != 0 { return 1 }

    println("No-GC checks passed: S driver")
    0
}
