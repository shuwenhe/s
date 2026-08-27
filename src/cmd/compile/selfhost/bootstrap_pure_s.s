package main

use std.fs.write_text_file
use std.io.eprintln
use std.io_syscall.mkdir
use std.process.run_process
use std.slices

func main() {
    compiler_src := "./src/cmd/compile/selfhost/compiler.s"
    output_dir := "./.bootstrap/selfhost"
    seed_compiler := "./bin/s_seed"
    ir_codegen_bin := "./src/cmd/compile/selfhost/ir_to_binary"

    eprintln("")
    eprintln("=== S Compiler Pure S Bootstrap ===")
    eprintln("")
    eprintln("source: " + compiler_src)
    eprintln("workdir: " + output_dir)
    eprintln("seed: " + seed_compiler)
    eprintln("ir-codegen: " + ir_codegen_bin)

    if !ensure_dir(output_dir) {
        return 1
    }

    return bootstrap_three_stage(compiler_src, output_dir, seed_compiler, ir_codegen_bin)
}

func ensure_dir(string path) bool {
    if mkdir(path) != 0 {
        return false
    }
    true
}

func bootstrap_three_stage(
    string compiler_src,
    string output_dir,
    string seed_compiler,
    string ir_codegen_bin
) int {
    stage1_ir := output_dir + "/stage1.ir"
    stage1_bin := output_dir + "/stage1"
    stage2_ir := output_dir + "/stage2.ir"
    stage2_bin := output_dir + "/stage2"
    stage3_ir := output_dir + "/stage3.ir"
    stage3_bin := output_dir + "/stage3"

    eprintln("[1/5] building stage1 IR with the trusted seed")
    stage1_argv := string[]{}
    stage1_argv = append(stage1_argv, seed_compiler)
    stage1_argv = append(stage1_argv, compiler_src)
    stage1_argv = append(stage1_argv, stage1_ir)
    if run_checked(stage1_argv) != 0 {
        return 1
    }

    eprintln("[2/5] lowering stage1 IR to a runnable compiler")
    string[] stage1_bin_argv = string[]()
    stage1_bin_argv = append(stage1_bin_argv, seed_compiler)
    stage1_bin_argv = append(stage1_bin_argv, "--emit-standalone-amd64")
    stage1_bin_argv = append(stage1_bin_argv, stage1_ir)
    stage1_bin_argv = append(stage1_bin_argv, stage1_bin)
    if run_checked(stage1_bin_argv) != 0 {
        return 1
    }

    eprintln("[3/5] recompiling compiler.s with stage1")
    string[] stage2_argv = string[]()
    stage2_argv = append(stage2_argv, stage1_bin)
    stage2_argv = append(stage2_argv, compiler_src)
    stage2_argv = append(stage2_argv, stage2_ir)
    if run_checked(stage2_argv) != 0 {
        return 1
    }
    string[] stage2_bin_argv = string[]()
    stage2_bin_argv = append(stage2_bin_argv, stage1_bin)
    stage2_bin_argv = append(stage2_bin_argv, "--emit-standalone-amd64")
    stage2_bin_argv = append(stage2_bin_argv, stage2_ir)
    stage2_bin_argv = append(stage2_bin_argv, stage2_bin)
    if run_checked(stage2_bin_argv) != 0 {
        return 1
    }

    eprintln("[4/5] recompiling compiler.s with stage2")
    string[] stage3_argv = string[]()
    stage3_argv = append(stage3_argv, stage2_bin)
    stage3_argv = append(stage3_argv, compiler_src)
    stage3_argv = append(stage3_argv, stage3_ir)
    if run_checked(stage3_argv) != 0 {
        return 1
    }
    string[] stage3_bin_argv = string[]()
    stage3_bin_argv = append(stage3_bin_argv, stage2_bin)
    stage3_bin_argv = append(stage3_bin_argv, "--emit-standalone-amd64")
    stage3_bin_argv = append(stage3_bin_argv, stage3_ir)
    stage3_bin_argv = append(stage3_bin_argv, stage3_bin)
    if run_checked(stage3_bin_argv) != 0 {
        return 1
    }

    eprintln("[5/5] verifying convergence")
    string[] cmp_ir_argv = string[]()
    cmp_ir_argv = append(cmp_ir_argv, "cmp")
    cmp_ir_argv = append(cmp_ir_argv, stage2_ir)
    cmp_ir_argv = append(cmp_ir_argv, stage3_ir)
    if run_checked(cmp_ir_argv) != 0 {
        eprintln("bootstrap failed: stage2.ir and stage3.ir differ")
        return 1
    }
    string[] cmp_bin_argv = string[]()
    cmp_bin_argv = append(cmp_bin_argv, "cmp")
    cmp_bin_argv = append(cmp_bin_argv, stage2_bin)
    cmp_bin_argv = append(cmp_bin_argv, stage3_bin)
    if run_checked(cmp_bin_argv) != 0 {
        eprintln("bootstrap failed: stage2 and stage3 binaries differ")
        return 1
    }

    manifest := make_manifest(stage1_ir, stage1_bin, stage2_ir, stage2_bin, stage3_ir, stage3_bin)
    if write_text_file(output_dir + "/manifest.txt", manifest) != 0 {
        eprintln("bootstrap failed: unable to write manifest")
        return 1
    }

    eprintln("bootstrap complete: stage2 and stage3 converge")
    eprintln("installed candidate: " + stage2_bin)
    0
}

func run_checked([]string argv) int {
    exit_code := run_process(argv)
    if exit_code != 0 {
        eprintln("bootstrap command failed")
        return 1
    }
    0
}

func make_manifest(
    string stage1_ir,
    string stage1_bin,
    string stage2_ir,
    string stage2_bin,
    string stage3_ir,
    string stage3_bin
) string {
    out := "s-bootstrap-manifest-v1\n"
    out = out + "stage1.ir=" + stage1_ir + "\n"
    out = out + "stage1=" + stage1_bin + "\n"
    out = out + "stage2.ir=" + stage2_ir + "\n"
    out = out + "stage2=" + stage2_bin + "\n"
    out = out + "stage3.ir=" + stage3_ir + "\n"
    out = out + "stage3=" + stage3_bin + "\n"
    out
}
